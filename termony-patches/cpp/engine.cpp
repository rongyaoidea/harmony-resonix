// engine.cpp — resonix-harmony 引擎进程管理实现
//
// 设计要点（对应 docs/DEPLOY.md）：
// 1. 引擎 = qemu-vroot-aarch64（用户态 proot 模拟）+ Alpine rootfs 中的
//    resonix/bridge 静态二进制。qemu-vroot 不创建独立网络栈，rootfs 内
//    监听的 127.0.0.1:PORT 在宿主（鸿蒙 app 进程网络命名空间）直接可达，
//    ArkTS WebView 可直连。
// 2. setsid 脱离控制终端：引擎随应用存活，但不随 WebView 页面切换而中断；
//    日志落 <filesDir>/engine.log 便于排障。
// 3. 不依赖 Termony 原有 PTY/渲染管线，改动零侵入。
#include "engine.h"

#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/wait.h>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "hilog/log.h"

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x0000
#define LOG_TAG "resonix-engine"

namespace engine_napi {

static pid_t g_engine_pid = -1;

static std::string NapiGetString(napi_env env, napi_value v) {
    size_t len = 0;
    napi_get_value_string_utf8(env, v, nullptr, 0, &len);
    std::string out(len, '\0');
    if (len > 0) {
        napi_get_value_string_utf8(env, v, out.data(), len + 1, &len);
        out.resize(len);
    }
    return out;
}

static std::vector<std::string> NapiGetStringArray(napi_env env, napi_value v) {
    std::vector<std::string> out;
    bool is_array = false;
    if (napi_is_array(env, v, &is_array) != napi_ok || !is_array) {
        return out;
    }
    uint32_t n = 0;
    napi_get_array_length(env, v, &n);
    out.reserve(n);
    for (uint32_t i = 0; i < n; i++) {
        napi_value item = nullptr;
        if (napi_get_element(env, v, i, &item) != napi_ok) continue;
        napi_valuetype t = napi_undefined;
        napi_typeof(env, item, &t);
        if (t == napi_string) out.push_back(NapiGetString(env, item));
    }
    return out;
}

napi_value StartEngine(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value argv[4] = {nullptr, nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    if (argc < 2) {
        napi_throw_error(env, nullptr, "StartEngine(cmd, args[, envPairs[, cwd]])");
        napi_value err;
        napi_create_double(env, -1, &err);
        return err;
    }

    std::string cmd = NapiGetString(env, argv[0]);
    std::vector<std::string> args = NapiGetStringArray(env, argv[1]);
    std::vector<std::string> envPairs = (argc >= 3 && argv[2] != nullptr)
        ? NapiGetStringArray(env, argv[2]) : std::vector<std::string>();
    std::string cwd = (argc >= 4 && argv[3] != nullptr)
        ? NapiGetString(env, argv[3]) : "/storage/Users/currentUser";

    // 引擎日志：应用沙箱 files 目录（ArkTS 侧 context.filesDir 同一路径）
    std::string logPath = "/data/storage/el2/base/haps/entry/files/engine.log";

    // 若已有引擎在跑，先礼貌终止，避免端口冲突
    if (g_engine_pid > 0 && kill(g_engine_pid, 0) == 0) {
        OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG,
                     "engine pid=%d still running, stopping first", g_engine_pid);
        kill(-g_engine_pid, SIGTERM);
        int status = 0;
        for (int i = 0; i < 20; i++) {
            if (waitpid(g_engine_pid, &status, WNOHANG) != 0) break;
            usleep(100 * 1000);
        }
        if (kill(g_engine_pid, 0) == 0) kill(-g_engine_pid, SIGKILL);
        waitpid(g_engine_pid, &status, 0);
    }

    pid_t pid = fork();
    if (pid < 0) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "fork failed");
        napi_value err;
        napi_create_double(env, -1, &err);
        return err;
    }
    if (pid == 0) {
        // —— 子进程 ——
        setsid();  // 新会话，脱离 UI 线程信号组
        int logfd = open(logPath.c_str(), O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (logfd >= 0) { dup2(logfd, STDOUT_FILENO); dup2(logfd, STDERR_FILENO); close(logfd); }
        int nullfd = open("/dev/null", O_RDONLY);
        if (nullfd >= 0) { dup2(nullfd, STDIN_FILENO); close(nullfd); }

        // 与 Termony::Fork() 对齐的环境基线
        setenv("HOME", cwd.c_str(), 1);
        setenv("PWD", cwd.c_str(), 1);
        setenv("LD_LIBRARY_PATH", "/data/app/base.org/base_1.0/lib", 1);
        setenv("TMUX_TMPDIR", "/data/storage/el2/base/cache", 1);
        for (const auto &kv : envPairs) {
            size_t eq = kv.find('=');
            if (eq != std::string::npos && eq > 0) {
                setenv(kv.substr(0, eq).c_str(), kv.substr(eq + 1).c_str(), 1);
            }
        }
        if (chdir(cwd.c_str()) != 0) {
            // cwd 不存在时回退，保证引擎仍可启动
            chdir("/storage/Users/currentUser");
        }

        std::vector<char *> argv_vec;
        argv_vec.push_back(const_cast<char *>(cmd.c_str()));
        for (const auto &a : args) argv_vec.push_back(const_cast<char *>(a.c_str()));
        argv_vec.push_back(nullptr);
        execv(cmd.c_str(), argv_vec.data());
        _exit(127);  // execv 失败
    }

    // —— 父进程 ——
    g_engine_pid = pid;
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
                 "engine started: %s, pid=%d, log=%s", cmd.c_str(), pid, logPath.c_str());

    napi_value result;
    napi_create_double(env, static_cast<double>(pid), &result);
    return result;
}

napi_value StopEngine(napi_env env, napi_callback_info) {
    if (g_engine_pid <= 0) {
        napi_value ok;
        napi_get_boolean(env, false, &ok);
        return ok;
    }
    kill(-g_engine_pid, SIGTERM);  // 对整个进程组发信号（qemu-vroot+引擎）
    int status = 0;
    for (int i = 0; i < 30; i++) {
        if (waitpid(g_engine_pid, &status, WNOHANG) != 0) break;
        usleep(100 * 1000);
    }
    if (kill(g_engine_pid, 0) == 0) {
        kill(-g_engine_pid, SIGKILL);
        waitpid(g_engine_pid, &status, 0);
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "engine stopped (pid=%d)", g_engine_pid);
    g_engine_pid = -1;
    napi_value ok;
    napi_get_boolean(env, true, &ok);
    return ok;
}

napi_value EngineRunning(napi_env env, napi_callback_info) {
    bool running = false;
    if (g_engine_pid > 0) {
        int status = 0;
        pid_t r = waitpid(g_engine_pid, &status, WNOHANG);
        // 0 = 仍在运行；>0 = 已退出（已 reap，重置避免脏值）
        if (r == 0) {
            running = true;
        } else if (r > 0) {
            g_engine_pid = -1;
        }
        // -1 = ECHILD（非子进程/已 reap）：按未运行处理，pid 保持由 StopEngine 负责清理
    }
    napi_value out;
    napi_get_boolean(env, running, &out);
    return out;
}

} // namespace engine_napi

