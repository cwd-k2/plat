use std::path::PathBuf;
use std::process::Command;

fn plat_verify_bin() -> PathBuf {
    let mut path = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    path.pop(); path.pop(); path.push("target");
    path.push("debug");
    path.push("plat-verify");
    path
}

fn example_dir() -> PathBuf {
    let mut path = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    path.pop(); path.pop(); path.push("examples");
    path.push("cross-language");
    path
}

fn build() {
    let status = Command::new("cargo")
        .args(["build"])
        .current_dir(env!("CARGO_MANIFEST_DIR"))
        .status()
        .expect("failed to build");
    assert!(status.success(), "cargo build failed");
}

#[test]
fn cross_language_all_pass() {
    build();

    let dir = example_dir();
    let output = Command::new(plat_verify_bin())
        .arg(dir.join("manifest.json"))
        .arg("--config")
        .arg(dir.join("plat-verify.toml"))
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

    // Both services should appear in output
    assert!(stdout.contains("[go-api]"), "should contain go-api service");
    assert!(stdout.contains("[ts-web]"), "should contain ts-web service");

    // Both should report "All checks passed"
    let pass_count = stdout.matches("All checks passed").count();
    assert_eq!(pass_count, 2, "both services should pass all checks");
}

#[test]
fn cross_language_json_output() {
    build();

    let dir = example_dir();
    let output = Command::new(plat_verify_bin())
        .arg(dir.join("manifest.json"))
        .arg("--config")
        .arg(dir.join("plat-verify.toml"))
        .arg("--format")
        .arg("json")
        .output()
        .expect("failed to run plat-verify");

    let stdout = String::from_utf8_lossy(&output.stdout);
    println!("json output:\n{stdout}");

    // Output is two JSON objects (one per service); use stream deserializer
    let jsons: Vec<serde_json::Value> = serde_json::Deserializer::from_str(&stdout)
        .into_iter::<serde_json::Value>()
        .map(|r| r.expect("each service output should be valid JSON"))
        .collect();

    assert_eq!(jsons.len(), 2, "should produce two JSON outputs");

    let go = jsons.iter().find(|j| j["language"] == "go").expect("should have go service");
    assert_eq!(go["summary"]["errors"], 0);

    let ts = jsons.iter().find(|j| j["language"] == "typescript").expect("should have ts service");
    assert_eq!(ts["summary"]["errors"], 0);
}

#[test]
fn cross_language_quiet_mode() {
    build();

    let dir = example_dir();
    let output = Command::new(plat_verify_bin())
        .arg(dir.join("manifest.json"))
        .arg("--config")
        .arg(dir.join("plat-verify.toml"))
        .arg("--quiet")
        .output()
        .expect("failed to run plat-verify");

    let stdout = String::from_utf8_lossy(&output.stdout);
    println!("quiet output:\n{stdout}");

    assert_eq!(output.status.code(), Some(0));
    assert!(stdout.contains("[go-api]"), "quiet mode should show service names");
    assert!(stdout.contains("[ts-web]"), "quiet mode should show service names");
    assert!(stdout.contains("0 error(s)"), "should show zero errors");
}
