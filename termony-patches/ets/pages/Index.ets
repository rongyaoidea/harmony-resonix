// Index.ets — resonix-harmony 前端（基于 Termony Index.ets 改造）
//
// 改造说明：
// 1. 原 Termony 终端（XComponent + alacritty C++ 渲染）整体保留，挪入 TerminalTab；
// 2. 新增 AgentTab：Web 组件直连本机引擎 http://127.0.0.1:8080（qemu-vroot
//    为用户态模拟、无独立网络栈，rootfs 内监听的端口宿主直接可达）；
// 3. 引擎生命周期：进入 AgentTab 时 testNapi.startEngine(...) 拉起
//    qemu-vroot + Alpine rootfs 中的 resonix 桥服务，轮询探活后加载 Web UI；
// 4. 零改动复用 Termony 的 HNP/权限/C++ 终端管线。
import { hilog } from '@kit.PerformanceAnalysisKit';
import testNapi from 'libentry.so';
import { taskpool } from '@kit.ArkTS';
import { util } from '@kit.ArkTS';
import fs from '@ohos.file.fs';
import { pasteboard } from '@kit.BasicServicesKit';
import { abilityAccessCtrl, bundleManager, Permissions } from '@kit.AbilityKit';
import promptAction from '@ohos.promptAction';
import { webview } from '@kit.ArkWeb';
import { http } from '@kit.NetworkKit';

const DOMAIN = 0x0000;
const TAG = 'resonix-harmony';

// ============================================================================
// 引擎配置
// ============================================================================
const ENGINE_PORT = 8080;
// rootfs 解压目录（首次部署见 docs/DEPLOY.md：hdc file send + tar 解压，
// 或在终端 Tab 里手动操作）
const ROOTFS_DIR = '/data/storage/el2/base/haps/entry/files/alpine_rootfs';
const ENGINE_LOG = '/data/storage/el2/base/haps/entry/files/engine.log';

// 启动命令（模式 B：qemu-vroot + Alpine rootfs —— Termony 已验证路径）
// bridge = engine/bridge 编译产物（Go 静态二进制，托管 Web UI 并桥接引擎）。
// 引擎命令已按上游确认：reasonix acp（docs/ACP.zh-CN.md，bridge 默认值一致）。
const ENGINE_CMD = '/data/app/bin/qemu-vroot-aarch64';
const ENGINE_ARGS: string[] = [
  '-E', 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
  '-E', 'HOME=/root',
  '-E', 'LANG=C.UTF-8',
  '-E', 'SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt',
  '-L', ROOTFS_DIR,
  '/usr/local/bin/bridge',
  '--addr', `127.0.0.1:${ENGINE_PORT}`,
];
const ENGINE_ENV: string[] = [
  `ENGINE_LOG=${ENGINE_LOG}`,
];
const ENGINE_CWD = '/storage/Users/currentUser';

// rootfs 未部署时的引导命令（在 Terminal Tab 粘贴执行；两个上传文件
// 需在 PC 侧用 hdc file send 放入 files/ 目录，见 docs/DEPLOY.md §1）
const ROOTFS_SETUP_CMD: string =
  'cd /data/storage/el2/base/haps/entry/files\n' +
  'mkdir -p alpine_rootfs\n' +
  'tar xzf alpine.tar.gz -C alpine_rootfs\n' +
  'chmod +x alpine_rootfs/usr/local/bin/bridge\n' +
  '# 注：alpine.tar.gz 与 bridge 需先在 PC 侧执行\n' +
  '#   hdc file send alpine.tar.gz  /data/app/el2/100/base/<bundle>/haps/entry/files/\n' +
  '#   hdc file send bridge         /data/app/el2/100/base/<bundle>/haps/entry/files/';

async function probeEngine(port: number): Promise<boolean> {
  const req = http.createHttp();
  try {
    const resp = await req.request(`http://127.0.0.1:${port}/`, {
      method: http.RequestMethod.GET,
      connectTimeout: 2000,
      readTimeout: 2000,
      expectDataType: http.HttpDataType.STRING,
    });
    // 引擎服务只要应答（含 4xx/5xx）即视为端口可达
    return resp.responseCode >= 200 && resp.responseCode < 600;
  } catch (e) {
    return false;
  } finally {
    req.destroy();
  }
}

// ============================================================================
// AgentTab — Web UI（resonix 图形前端）
// ============================================================================
@Component
struct AgentTab {
  @State engineUrl: string = '';
  @State engineStatus: string = '未启动';
  @State bootFailed: boolean = false;
  @State rootfsMissing: boolean = false;
  webController: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    this.bootEngine();
  }

  async bootEngine(): Promise<void> {
    this.bootFailed = false;
    // rootfs 首启引导：未部署 Alpine rootfs 时直接给出指引，不盲目拉引擎
    let rootfsReady = false;
    try {
      rootfsReady = fs.accessSync(ROOTFS_DIR);
    } catch (e) {
      rootfsReady = false;
    }
    if (!rootfsReady) {
      this.rootfsMissing = true;
      this.engineStatus = '尚未部署 Alpine rootfs';
      hilog.warn(DOMAIN, TAG, 'rootfs missing: %{public}s', ROOTFS_DIR);
      return;
    }
    this.rootfsMissing = false;
    this.engineStatus = '启动引擎…';
    const pid = testNapi.startEngine(ENGINE_CMD, ENGINE_ARGS, ENGINE_ENV, ENGINE_CWD);
    hilog.info(DOMAIN, TAG, 'startEngine pid=%{public}d', pid);
    if (pid <= 0) {
      this.engineStatus = `引擎启动失败(pid=${pid})，日志：${ENGINE_LOG}`;
      this.bootFailed = true;
      return;
    }
    // 探活：最多等 15s（rootfs 首次启动略慢）
    for (let i = 0; i < 30; i++) {
      if (await probeEngine(ENGINE_PORT)) {
        this.engineStatus = '运行中';
        this.engineUrl = `http://127.0.0.1:${ENGINE_PORT}/`;
        this.webController.loadUrl(this.engineUrl);
        return;
      }
      await this.sleep(500);
    }
    this.engineStatus = `引擎探活超时，日志：${ENGINE_LOG}`;
    this.bootFailed = true;
  }

  sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(resolve, ms);
    });
  }

  build() {
    Stack() {
      if (this.engineUrl === '') {
        // 引擎未就绪：状态页
        Column({ space: 12 }) {
          Text('resonix for HarmonyOS').fontSize(22).fontWeight(FontWeight.Bold)
          Text(this.engineStatus).fontSize(14).opacity(0.8)
          if (this.rootfsMissing) {
            // 首启引导：三步部署说明（在终端 Tab 内执行，无需 hdc）
            Column({ space: 6 }) {
              Text('首次使用需要部署 Alpine rootfs：')
                .fontSize(13).fontWeight(FontWeight.Medium)
              Text('1. 电脑上下载 Alpine minirootfs（aarch64）')
                .fontSize(12).opacity(0.85)
              Text('2. hdc file send 推送到应用 files 目录')
                .fontSize(12).opacity(0.85)
              Text('3. 本页切到「终端」Tab 执行 tar 解压')
                .fontSize(12).opacity(0.85)
              Text('详见工程 docs/DEPLOY.md 第 1 节（含可复制命令）')
                .fontSize(12).opacity(0.6)
              Button('复制部署命令').onClick(() => {
                const paste = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, ROOTFS_SETUP_CMD);
                pasteboard.getSystemPasteboard().setData(paste);
                promptAction.showToast({ message: '已复制，到「终端」Tab 粘贴执行' });
              })
              Button('重试').onClick(() => {
                this.engineUrl = '';
                this.bootEngine();
              })
            }
            .alignItems(HorizontalAlign.Start)
            .padding(12)
            .borderRadius(10)
            .backgroundColor('#1c2029')
          }
          if (this.bootFailed) {
            Button('重试').onClick(() => {
              this.engineUrl = '';
              this.bootEngine();
            })
            Text(`排障：终端 Tab 执行 tail -50 ${ENGINE_LOG}`)
              .fontSize(12).opacity(0.6)
          }
          LoadingProgress().width(36).height(36)
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        // 引擎就绪：Web UI
        Column() {
          Web({ src: this.engineUrl, controller: this.webController })
            .domStorageAccess(true)
            .javaScriptAccess(true)
            .fileAccess(true)
            .databaseAccess(true)
            .zoomAccess(true)
            .width('100%')
            .layoutWeight(1)
        }
        .width('100%').height('100%')
      }
    }
    .width('100%').height('100%')
  }
}

// ============================================================================
// TerminalTab — 原 Termony 终端（全量保留）
// ============================================================================
let keyMapping: Map<string, number[]> = new Map();
keyMapping.set("KEYCODE_SPACE", [0x20]);
keyMapping.set("KEYCODE_ENTER", [0x0d]);
keyMapping.set("KEYCODE_DEL", [0x7f]);
keyMapping.set("KEYCODE_TAB", [0x09]);
keyMapping.set("KEYCODE_ESCAPE", [0x1b]);
keyMapping.set("KEYCODE_DPAD_UP", [0x1b, 0x5b, 0x41]);
keyMapping.set("KEYCODE_DPAD_DOWN", [0x1b, 0x5b, 0x42]);
keyMapping.set("KEYCODE_DPAD_RIGHT", [0x1b, 0x5b, 0x43]);
keyMapping.set("KEYCODE_DPAD_LEFT", [0x1b, 0x5b, 0x44]);
keyMapping.set("KEYCODE_F1", [0x1b, 0x4f, 0x50]);
keyMapping.set("KEYCODE_F2", [0x1b, 0x4f, 0x51]);
keyMapping.set("KEYCODE_F3", [0x1b, 0x4f, 0x52]);
keyMapping.set("KEYCODE_F4", [0x1b, 0x4f, 0x53]);
keyMapping.set("KEYCODE_F5", [0x1b, 0x5b, 0x31, 0x35, 0x7e]);
keyMapping.set("KEYCODE_F6", [0x1b, 0x5b, 0x31, 0x37, 0x7e]);
keyMapping.set("KEYCODE_F7", [0x1b, 0x5b, 0x31, 0x38, 0x7e]);
keyMapping.set("KEYCODE_F8", [0x1b, 0x5b, 0x31, 0x39, 0x7e]);
keyMapping.set("KEYCODE_F10", [0x1b, 0x5b, 0x32, 0x31, 0x7e]);
keyMapping.set("KEYCODE_F11", [0x1b, 0x5b, 0x32, 0x33, 0x7e]);
keyMapping.set("KEYCODE_F12", [0x1b, 0x5b, 0x32, 0x34, 0x7e]);

class MyXComponentController extends XComponentController {
  onSurfaceCreated(surfaceId: string): void {
    hilog.info(DOMAIN, 'testTag', 'onSurfaceCreated surfaceId: %{public}s', surfaceId);
    testNapi.createSurface(BigInt(surfaceId));
  }

  onSurfaceChanged(surfaceId: string, rect: SurfaceRect): void {
    hilog.info(DOMAIN, 'testTag', 'onSurfaceChanged surfaceId: %{public}s rect: %{public}s', surfaceId, JSON.stringify(rect));
    testNapi.resizeSurface(BigInt(surfaceId), rect.surfaceWidth, rect.surfaceHeight);
  }

  onSurfaceDestroyed(surfaceId: string): void {
    hilog.info(DOMAIN, 'testTag', 'onSurfaceDestroyed surfaceId: %{public}s', surfaceId);
    testNapi.destroySurface(BigInt(surfaceId))
  }
}

@Component
struct TerminalTab {
  @State leftCtrlPressed: boolean = false;
  @State touchState: Map<number, number> = new Map();
  xComponentController: XComponentController = new MyXComponentController();
  timer: number = -1;
  terminalStarted: boolean = false;

  aboutToAppear(): void {
    // 原 Index.ets 顶层的 testNapi.run()（C++ 侧有幂等保护），挪到首次显示时执行
    if (!this.terminalStarted) {
      testNapi.run();
      this.terminalStarted = true;
    }
    this.timer = setInterval(() => {
      let res: string | undefined = testNapi.checkCopy();
      if (res !== undefined) {
        hilog.info(DOMAIN, 'testTag', 'Copy to pasteboard in ArkTS: %{public}s', res);
        let base64 = new util.Base64Helper();
        let data = base64.decodeSync(res);
        let textDecoder = util.TextDecoder.create('utf-8');
        let result = textDecoder.decodeToString(data);
        hilog.info(DOMAIN, 'testTag', 'Copy to pasteboard in ArkTS decoded: %{public}s', result);
        let pasteData: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, result);
        let systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
        systemPasteboard.setData(pasteData, (err, data) => {
          if (err) {
            hilog.info(0x0000, 'mainTag', 'Failed to set pasteboard: %{public}s', JSON.stringify(err));
            return;
          } else {
            promptAction.showToast({
              message: "Copied to pasteboard",
              duration: 1000,
              bottom: "center",
            })
          }
        });
      }

      if (testNapi.checkPaste()) {
        // need to paste
        const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
        atManager.requestPermissionsFromUser(getContext(), ['ohos.permission.READ_PASTEBOARD']).then(async () => {
          let systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
          let data = await systemPasteboard.getData();
          hilog.info(DOMAIN, 'testTag', 'Got pasteboard data: %{public}s', JSON.stringify(data));
          let count = data.getRecordCount();
          for (let i = 0;i < count;i++) {
            let record = data.getRecord(i);
            hilog.info(DOMAIN, 'testTag', 'Got pasteboard record: %{public}s', JSON.stringify(record));
            let plainText: string = record.plainText;

            let textEncoder = util.TextEncoder.create('utf-8');
            let encodeResult = textEncoder.encodeInto(plainText);

            let base64 = new util.Base64Helper();
            let encoded = base64.encodeToStringSync(encodeResult);
            testNapi.pushPaste(encoded);
          }

          promptAction.showToast({
            message: "Pasted from pasteboard",
            duration: 1000,
            bottom: "center",
          })
        });
      }
    }, 100);
  }

  onPageHide() {
    clearInterval(this.timer);
  }

  @Builder MenuBuilder() {
    Menu() {
      MenuItem({ content: "Paste" })
        .onClick(async () => {
          const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
          await atManager.requestPermissionsFromUser(getContext(), ['ohos.permission.READ_PASTEBOARD']);
          let systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
          let data = await systemPasteboard.getData();
          hilog.info(DOMAIN, 'testTag', 'Got pasteboard data: %{public}s', JSON.stringify(data));
          let count = data.getRecordCount();
          for (let i = 0;i < count;i++) {
            let record = data.getRecord(i);
            hilog.info(DOMAIN, 'testTag', 'Got pasteboard record: %{public}s', JSON.stringify(record));
            let plainText: string = record.plainText;

            let textEncoder = util.TextEncoder.create('utf-8');
            let encodeResult = textEncoder.encodeInto(plainText);
            testNapi.send(encodeResult.buffer);
          }
        })
    }
  }

  build() {
    Row() {
      Column() {
        XComponent({
          type: XComponentType.SURFACE,
          controller: this.xComponentController
        })
        .bindContextMenu(this.MenuBuilder, ResponseType.RightClick)
      }
      .width('100%')
    }
    .height('100%')
    .onTouch((event: TouchEvent) => {
      for (let touch of event.touches) {
        if (touch.type === TouchType.Down) {
          this.touchState.set(touch.id, touch.y);
        } else if (touch.type === TouchType.Move) {
          let offset = vp2px(this.touchState.get(touch.id) as number - touch.y);
          this.touchState.set(touch.id, touch.y);
          testNapi.scroll(offset);
        }
      }
    })
    .onKeyEvent((event: KeyEvent) => {
      hilog.info(DOMAIN, 'testTag', 'Got key: %{public}s', JSON.stringify(event));
      if (event.type === KeyType.Down) {
        if (this.leftCtrlPressed && event.unicode as number >= 97 && event.unicode as number <= 122) {
          let buffer = new ArrayBuffer(1);
          let view = new Uint8Array(buffer);
          view[0] = event.unicode as number - 97 + 1;
          testNapi.send(buffer);
        } else if (event.keyText === "KEYCODE_EQUALS") {
          let buffer = new ArrayBuffer(1);
          let view = new Uint8Array(buffer);
          if (event.unicode === 0x3d) {
            view[0] = 0x2b;
          } else {
            view[0] = 0x3d;
          }
          testNapi.send(buffer);
        } else if (event.unicode !== 0) {
          let textEncoder = util.TextEncoder.create('utf-8');
          let encodeResult = textEncoder.encodeInto(String.fromCharCode(event.unicode as number));
          testNapi.send(encodeResult.buffer);
        } else {
          if (event.keyText === "KEYCODE_CTRL_LEFT") {
            this.leftCtrlPressed = true;
          } else if (keyMapping.has(event.keyText)) {
            let data: number[] = keyMapping.get(event.keyText)!;
            let buffer = new ArrayBuffer(data.length);
            let view = new Uint8Array(buffer);
            let i = 0;
            for (let byte of data) {
              view[i] = byte;
              i += 1;
            }
            testNapi.send(buffer);
          }
        }
      } else if (event.type === KeyType.Up) {
        if (event.keyText === "KEYCODE_CTRL_LEFT") {
          this.leftCtrlPressed = false;
        }
      }
    })
  }
}

// ============================================================================
// Index — 双 Tab 宿主：Agent（Web UI）/ Terminal（原终端）
// ============================================================================
@Entry
@Component
struct Index {
  build() {
    Tabs({ barPosition: BarPosition.End }) {
      TabContent() {
        AgentTab()
      }
      .tabBar('Agent')

      TabContent() {
        TerminalTab()
      }
      .tabBar('Terminal')
    }
    .width('100%')
    .height('100%')
  }
}
