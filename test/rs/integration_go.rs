use std::path::PathBuf;
use std::process::Command;

fn plat_verify_bin() -> PathBuf {
    // cargo test builds the binary in target/debug
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
    path.push("go-clean-arch");
    path
}

#[test]
fn go_clean_arch_all_pass() {
    // First ensure the binary is built
    let status = Command::new("cargo")
        .args(["build"])
        .current_dir(env!("CARGO_MANIFEST_DIR"))
        .status()
        .expect("failed to build");
    assert!(status.success(), "cargo build failed");

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

    // Should exit 0 (no errors)
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
fn go_clean_arch_json_output() {
    let status = Command::new("cargo")
        .args(["build"])
        .current_dir(env!("CARGO_MANIFEST_DIR"))
        .status()
        .expect("failed to build");
    assert!(status.success());

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

    // Should be valid JSON
    let json: serde_json::Value =
        serde_json::from_str(&stdout).expect("output should be valid JSON");

    assert_eq!(json["name"], "order-service");
    assert_eq!(json["language"], "go");
    assert_eq!(json["summary"]["errors"], 0);
}

#[test]
fn go_missing_type_reports_error() {
    let status = Command::new("cargo")
        .args(["build"])
        .current_dir(env!("CARGO_MANIFEST_DIR"))
        .status()
        .expect("failed to build");
    assert!(status.success());

    let dir = fixture_dir();
    // Point to an empty directory as root — everything should be "not found"
    let empty_dir = std::env::temp_dir().join("plat-verify-empty-test");
    let _ = std::fs::create_dir_all(&empty_dir);

    let output = Command::new(plat_verify_bin())
        .arg(dir.join("manifest.json"))
        .arg("--language")
        .arg("go")
        .arg("--root")
        .arg(&empty_dir)
        .output()
        .expect("failed to run plat-verify");

    let stdout = String::from_utf8_lossy(&output.stdout);
    println!("missing types output:\n{stdout}");

    // Should exit 1 (errors found)
    assert_eq!(
        output.status.code(),
        Some(1),
        "expected exit code 1 for missing types"
    );

    // Should report E001 for missing model
    assert!(stdout.contains("E001") || stdout.contains("E002") || stdout.contains("E003"),
        "should report existence errors");

    let _ = std::fs::remove_dir_all(&empty_dir);
}
