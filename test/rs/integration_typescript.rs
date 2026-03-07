use std::path::PathBuf;
use std::process::Command;

fn plat_verify_bin() -> PathBuf {
    let mut path = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    path.push("target");
    path.push("debug");
    path.push("plat-verify");
    path
}

fn fixture_dir() -> PathBuf {
    let mut path = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    path.push("test");
    path.push("fixtures");
    path.push("ts-hexagonal");
    path
}

fn build_binary() {
    let status = Command::new("cargo")
        .args(["build"])
        .current_dir(env!("CARGO_MANIFEST_DIR"))
        .status()
        .expect("failed to build");
    assert!(status.success(), "cargo build failed");
}

#[test]
fn ts_hexagonal_all_pass() {
    build_binary();

    let dir = fixture_dir();
    let output = Command::new(plat_verify_bin())
        .arg(dir.join("manifest.json"))
        .arg("--config")
        .arg(dir.join("plat-verify.toml"))
        .arg("--root")
        .arg(dir.join("src"))
        .output()
        .expect("failed to run plat-verify");

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);

    println!("stdout:\n{stdout}");
    println!("stderr:\n{stderr}");

    assert_eq!(
        output.status.code(),
        Some(0),
        "expected exit code 0 but got {:?}\nstdout: {stdout}\nstderr: {stderr}",
        output.status.code()
    );

    assert!(
        stdout.contains("order-service"),
        "output should contain architecture name"
    );
}

#[test]
fn ts_hexagonal_json_output() {
    build_binary();

    let dir = fixture_dir();
    let output = Command::new(plat_verify_bin())
        .arg(dir.join("manifest.json"))
        .arg("--config")
        .arg(dir.join("plat-verify.toml"))
        .arg("--root")
        .arg(dir.join("src"))
        .arg("--format")
        .arg("json")
        .output()
        .expect("failed to run plat-verify");

    let stdout = String::from_utf8_lossy(&output.stdout);
    println!("json output:\n{stdout}");

    let json: serde_json::Value =
        serde_json::from_str(&stdout).expect("output should be valid JSON");

    assert_eq!(json["name"], "order-service");
    assert_eq!(json["language"], "typescript");
    assert_eq!(json["summary"]["errors"], 0);
}

#[test]
fn ts_missing_type_reports_error() {
    build_binary();

    let dir = fixture_dir();
    let empty_dir = std::env::temp_dir().join("plat-verify-empty-ts-test");
    let _ = std::fs::create_dir_all(&empty_dir);

    let output = Command::new(plat_verify_bin())
        .arg(dir.join("manifest.json"))
        .arg("--language")
        .arg("typescript")
        .arg("--root")
        .arg(&empty_dir)
        .output()
        .expect("failed to run plat-verify");

    let stdout = String::from_utf8_lossy(&output.stdout);
    println!("missing types output:\n{stdout}");

    assert_eq!(
        output.status.code(),
        Some(1),
        "expected exit code 1 for missing types"
    );

    assert!(
        stdout.contains("E001") || stdout.contains("E002") || stdout.contains("E003"),
        "should report existence errors"
    );

    let _ = std::fs::remove_dir_all(&empty_dir);
}
