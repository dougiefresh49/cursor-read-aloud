use serde::Serialize;

#[derive(Serialize)]
pub struct WsConfig {
    token: String,
    port: u16,
}

#[tauri::command]
fn ws_token() -> Result<WsConfig, String> {
    let home = dirs::home_dir().ok_or("no home directory")?;
    let tts = home.join(".cursor").join("tts");
    let token = std::fs::read_to_string(tts.join("panel_ws_token"))
        .map(|s| s.trim().to_string())
        .map_err(|e| e.to_string())?;
    let port = std::fs::read_to_string(tts.join("config.json"))
        .ok()
        .and_then(|s| serde_json::from_str::<serde_json::Value>(&s).ok())
        .and_then(|v| v.get("panel_port").and_then(|p| p.as_u64()))
        .unwrap_or(4780) as u16;
    Ok(WsConfig { token, port })
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![ws_token])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
