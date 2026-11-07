use std::sync::Mutex;
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{AppHandle, Emitter, Manager, PhysicalPosition, PhysicalSize, WebviewUrl, WebviewWindow, WebviewWindowBuilder, WindowEvent};
use tauri_plugin_dialog::DialogExt;
use tauri_plugin_global_shortcut::{Code, GlobalShortcutExt, Modifiers, Shortcut, ShortcutState};

/// 帯の位置と幅（次回起動時に復元）
#[derive(Serialize, Deserialize, Clone, Copy)]
struct Placement {
    x: i32,
    y: i32,
    width: u32,
}

#[derive(Default)]
struct AppState {
    /// Windows: ⌃⌥T で帯にフォーカスする直前に前面だったウィンドウ（戻すため）
    #[allow(dead_code)]
    prev_foreground: Mutex<isize>,
    last_saved: Mutex<Option<Instant>>,
}

// MARK: - コマンド（JS から呼ぶ）

// ファイルの場所は JS から受け取らない。必ずユーザーがダイアログで選んだファイルだけを読み書きする
// （画面側にスクリプトが紛れ込んでも、任意のファイルを読んだり書き換えたりできないように）

/// カスタム文に使うテキストファイルを選ばせて中身を返す。キャンセルなら None
#[tauri::command]
async fn pick_text_file(app: AppHandle, window: WebviewWindow) -> Result<Option<String>, String> {
    let Some(picked) = app.dialog().file().set_parent(&window).add_filter("テキスト", &["txt", "md", "csv"]).blocking_pick_file() else {
        return Ok(None);
    };
    let path = picked.into_path().map_err(|e| e.to_string())?;
    let len = std::fs::metadata(&path).map_err(|e| e.to_string())?.len();
    if len > 5 * 1024 * 1024 {
        return Err("ファイルが大きすぎます（5MB まで）".into());
    }
    std::fs::read_to_string(&path).map(Some).map_err(|e| e.to_string())
}

/// 保存先を選ばせて、行ごとの記録とキー別の記録を CSV で書き出す。書き出したパスを返す（キャンセルなら None）
#[tauri::command]
async fn export_csv(app: AppHandle, window: WebviewWindow, lines: String, keys: String) -> Result<Option<Vec<String>>, String> {
    let Some(picked) = app.dialog().file().set_parent(&window).set_file_name("typing-lines.csv").add_filter("CSV", &["csv"]).blocking_save_file() else {
        return Ok(None);
    };
    let path = picked.into_path().map_err(|e| e.to_string())?;
    let keys_path = path.with_file_name("typing-keys.csv");
    // Excel で文字化けしないよう BOM を付ける
    std::fs::write(&path, format!("\u{feff}{lines}")).map_err(|e| e.to_string())?;
    std::fs::write(&keys_path, format!("\u{feff}{keys}")).map_err(|e| e.to_string())?;
    Ok(Some(vec![path.display().to_string(), keys_path.display().to_string()]))
}

/// 内容の高さに合わせて帯を伸縮する（下端を固定して上に伸びる。画面からはみ出さない）
#[tauri::command]
fn fit_height(window: WebviewWindow, height: f64) -> Result<(), String> {
    let scale = window.scale_factor().map_err(|e| e.to_string())?;
    let h = (height * scale).ceil() as i32;
    if h < 20 {
        return Ok(());
    }
    let pos = window.outer_position().map_err(|e| e.to_string())?;
    let size = window.outer_size().map_err(|e| e.to_string())?;
    if (size.height as i32 - h).abs() <= 1 {
        return Ok(());
    }
    let bottom = pos.y + size.height as i32;
    let mut y = bottom - h;
    if let Ok(Some(m)) = window.current_monitor() {
        let top = m.position().y;
        let max = m.position().y + m.size().height as i32 - h;
        y = y.clamp(top, max.max(top));
    }
    window.set_size(PhysicalSize::new(size.width, h as u32)).map_err(|e| e.to_string())?;
    window.set_position(PhysicalPosition::new(pos.x, y)).map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
async fn open_window(app: AppHandle, kind: String) -> Result<(), String> {
    open_win(&app, &kind).map_err(|e| e.to_string())
}

#[tauri::command]
fn toggle_focus_cmd(app: AppHandle) {
    toggle_focus(&app);
}

#[tauri::command]
fn hide_main(app: AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.hide();
        give_back_focus(&app);
    }
}

#[tauri::command]
fn reset_position(app: AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        place_default(&w);
        let _ = w.show();
        let _ = w.set_focus();
    }
}

#[tauri::command]
fn quit(app: AppHandle) {
    quit_app(&app);
}

// MARK: - ウィンドウ操作

fn open_win(app: &AppHandle, kind: &str) -> tauri::Result<()> {
    if let Some(w) = app.get_webview_window(kind) {
        w.show()?;
        w.unminimize()?;
        w.set_focus()?;
        return Ok(());
    }
    let (url, title, w, h) = match kind {
        "settings" => ("settings.html", "TypingOverlay — 設定", 480.0, 780.0),
        "analytics" => ("analytics.html", "TypingOverlay — 統計・分析", 1080.0, 900.0),
        _ => return Ok(()),
    };
    let win = WebviewWindowBuilder::new(app, kind, WebviewUrl::App(url.into()))
        .title(title)
        .inner_size(w, h)
        .min_inner_size(420.0, 400.0)
        .theme(Some(tauri::Theme::Dark))
        .center()
        .build()?;
    win.set_focus()?;
    Ok(())
}

fn toggle_focus(app: &AppHandle) {
    let Some(w) = app.get_webview_window("main") else { return };
    let visible = w.is_visible().unwrap_or(false);
    let focused = w.is_focused().unwrap_or(false);
    if visible && focused {
        // キーフォーカスだけブラウザ側に返す（帯は表示したまま）
        give_back_focus(app);
    } else {
        remember_foreground(app);
        let _ = w.show();
        let _ = w.set_focus();
    }
}

#[cfg(windows)]
fn remember_foreground(app: &AppHandle) {
    use windows_sys::Win32::UI::WindowsAndMessaging::GetForegroundWindow;
    let hwnd = unsafe { GetForegroundWindow() } as isize;
    let own = app.get_webview_window("main").and_then(|w| w.hwnd().ok()).map(|h| h.0 as isize).unwrap_or(0);
    if hwnd != 0 && hwnd != own {
        *app.state::<AppState>().prev_foreground.lock().unwrap() = hwnd;
    }
}

#[cfg(windows)]
fn give_back_focus(app: &AppHandle) {
    use windows_sys::Win32::UI::WindowsAndMessaging::SetForegroundWindow;
    let prev = *app.state::<AppState>().prev_foreground.lock().unwrap();
    if prev != 0 {
        unsafe { SetForegroundWindow(prev as _) };
    }
}

#[cfg(target_os = "macos")]
fn remember_foreground(_app: &AppHandle) {}

#[cfg(target_os = "macos")]
fn give_back_focus(_app: &AppHandle) {
    use objc2::runtime::AnyObject;
    use objc2::{class, msg_send};
    // アプリを非アクティブにすると、直前に使っていたアプリ（ブラウザ）にフォーカスが戻る
    unsafe {
        let ns_app: *mut AnyObject = msg_send![class!(NSApplication), sharedApplication];
        let _: () = msg_send![ns_app, deactivate];
    }
}

#[cfg(not(any(windows, target_os = "macos")))]
fn remember_foreground(_app: &AppHandle) {}
#[cfg(not(any(windows, target_os = "macos")))]
fn give_back_focus(_app: &AppHandle) {}

fn quit_app(app: &AppHandle) {
    // 帯の JS に記録を書き出させてから終了
    let _ = app.emit("flush", ());
    let app = app.clone();
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_millis(350));
        app.exit(0);
    });
}

// MARK: - 位置の保存と復元

fn placement_path(app: &AppHandle) -> Option<std::path::PathBuf> {
    let dir = app.path().app_config_dir().ok()?;
    let _ = std::fs::create_dir_all(&dir);
    Some(dir.join("placement.json"))
}

fn save_placement(app: &AppHandle, w: &tauri::Window) {
    let st = app.state::<AppState>();
    {
        let mut last = st.last_saved.lock().unwrap();
        if last.map(|t| t.elapsed() < Duration::from_millis(300)).unwrap_or(false) {
            return;
        }
        *last = Some(Instant::now());
    }
    if let (Ok(p), Ok(s), Some(path)) = (w.outer_position(), w.outer_size(), placement_path(app)) {
        let pl = Placement { x: p.x, y: p.y + s.height as i32, width: s.width }; // y は下端
        let _ = std::fs::write(path, serde_json::to_string(&pl).unwrap_or_default());
    }
}

fn place_default(w: &WebviewWindow) {
    if let Ok(Some(m)) = w.primary_monitor().or_else(|_| w.current_monitor()) {
        let scale = m.scale_factor();
        let width = (980.0 * scale) as u32;
        let height = w.outer_size().map(|s| s.height).unwrap_or((200.0 * scale) as u32);
        let x = m.position().x + (m.size().width as i32 - width as i32) / 2;
        let y = m.position().y + m.size().height as i32 - height as i32 - (90.0 * scale) as i32;
        let _ = w.set_size(PhysicalSize::new(width, height));
        let _ = w.set_position(PhysicalPosition::new(x, y));
    }
}

fn restore_placement(app: &AppHandle, w: &WebviewWindow) {
    let saved = placement_path(app)
        .and_then(|p| std::fs::read_to_string(p).ok())
        .and_then(|s| serde_json::from_str::<Placement>(&s).ok());
    match saved {
        Some(pl) => {
            let h = w.outer_size().map(|s| s.height).unwrap_or(200);
            let _ = w.set_size(PhysicalSize::new(pl.width.max(420), h));
            let _ = w.set_position(PhysicalPosition::new(pl.x, pl.y - h as i32));
            // 画面外に出ていたら初期位置へ
            let on_screen = w
                .available_monitors()
                .map(|ms| {
                    ms.iter().any(|m| {
                        let (mx, my) = (m.position().x, m.position().y);
                        let (mw, mh) = (m.size().width as i32, m.size().height as i32);
                        pl.x + 100 > mx && pl.x < mx + mw && pl.y > my && pl.y - 40 < my + mh
                    })
                })
                .unwrap_or(true);
            if !on_screen {
                place_default(w);
            }
        }
        None => place_default(w),
    }
}

// MARK: - 起動

pub fn run() {
    tauri::Builder::default()
        .manage(AppState::default())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_clipboard_manager::init())
        .plugin(
            tauri_plugin_global_shortcut::Builder::new()
                .with_handler(|app, shortcut, event| {
                    if event.state() == ShortcutState::Pressed && shortcut.matches(Modifiers::CONTROL | Modifiers::ALT, Code::KeyT) {
                        toggle_focus(app);
                    }
                })
                .build(),
        )
        .invoke_handler(tauri::generate_handler![
            pick_text_file,
            export_csv,
            fit_height,
            open_window,
            toggle_focus_cmd,
            hide_main,
            reset_position,
            quit
        ])
        .setup(|app| {
            #[cfg(target_os = "macos")]
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);

            let handle = app.handle().clone();
            let main = app.get_webview_window("main").expect("main window");

            #[cfg(target_os = "macos")]
            if let Ok(ns) = main.ns_window() {
                use objc2::msg_send;
                use objc2::runtime::AnyObject;
                // すべてのデスクトップ + フルスクリーン中のアプリの上にも表示
                let behavior: usize = (1 << 0) | (1 << 8);
                unsafe {
                    let _: () = msg_send![ns as *mut AnyObject, setCollectionBehavior: behavior];
                }
            }

            restore_placement(&handle, &main);
            main.show()?;
            main.set_focus()?;

            // ⌃⌥T（Windows は Ctrl+Alt+T）
            let _ = app
                .global_shortcut()
                .register(Shortcut::new(Some(Modifiers::CONTROL | Modifiers::ALT), Code::KeyT));

            // タスクトレイ / メニューバー
            let toggle = MenuItem::with_id(app, "toggle", "表示 / フォーカス切替  (Ctrl+Alt+T)", true, None::<&str>)?;
            let analytics = MenuItem::with_id(app, "analytics", "統計・分析…", true, None::<&str>)?;
            let settings = MenuItem::with_id(app, "settings", "設定…", true, None::<&str>)?;
            let reset = MenuItem::with_id(app, "reset", "位置をリセット", true, None::<&str>)?;
            let hide = MenuItem::with_id(app, "hide", "隠す", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "終了", true, None::<&str>)?;
            let sep1 = PredefinedMenuItem::separator(app)?;
            let sep2 = PredefinedMenuItem::separator(app)?;
            let menu = Menu::with_items(app, &[&toggle, &sep1, &analytics, &settings, &reset, &sep2, &hide, &quit])?;
            let mut tray = TrayIconBuilder::with_id("tray")
                .tooltip("TypingOverlay")
                .menu(&menu)
                .show_menu_on_left_click(true)
                .on_menu_event(|app, e| match e.id.as_ref() {
                    "toggle" => toggle_focus(app),
                    "analytics" => { let _ = open_win(app, "analytics"); }
                    "settings" => { let _ = open_win(app, "settings"); }
                    "reset" => reset_position(app.clone()),
                    "hide" => hide_main(app.clone()),
                    "quit" => quit_app(app),
                    _ => {}
                });
            // macOS: メニューバーの他のアイコンと揃う単色のテンプレート画像（明るい/暗いメニューバーで自動で色が変わる）
            // Windows: タスクトレイはカラーのアプリアイコン（黒い単色だと暗いタスクバーで見えなくなる）
            #[cfg(target_os = "macos")]
            {
                let icon = tauri::image::Image::from_bytes(include_bytes!("../icons/tray-template.png"))?;
                tray = tray.icon(icon).icon_as_template(true);
            }
            #[cfg(not(target_os = "macos"))]
            if let Some(icon) = app.default_window_icon() {
                tray = tray.icon(icon.clone());
            }
            tray.build(app)?;
            Ok(())
        })
        .on_window_event(|w, e| {
            if w.label() != "main" {
                return;
            }
            match e {
                WindowEvent::Moved(_) | WindowEvent::Resized(_) => save_placement(w.app_handle(), w),
                WindowEvent::CloseRequested { api, .. } => {
                    // 閉じる操作（Alt+F4 など）は記録を保存してから終了
                    api.prevent_close();
                    quit_app(w.app_handle());
                }
                _ => {}
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running TypingOverlay");
}
