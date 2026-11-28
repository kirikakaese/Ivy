use std::fs;

fn main() {
    // The protos and the reported client version have one source each, shared with the Swift app.
    let protos = "../../SignalServiceKit/Protos/Specifications";
    prost_build::compile_protos(
        &[
            format!("{protos}/Provisioning.proto"),
            format!("{protos}/SignalIOS.proto"),
        ],
        &[protos],
    )
    .expect("protoc");

    let config = "../../Config/Ivy.xcconfig";
    println!("cargo:rerun-if-changed={config}");
    let text = fs::read_to_string(config).expect("Config/Ivy.xcconfig");
    let value = |name: &str| {
        text.lines()
            .find_map(|l| {
                l.strip_prefix(name)?
                    .trim_start()
                    .strip_prefix('=')
                    .map(|v| v.trim().to_owned())
            })
            .unwrap_or_else(|| panic!("{name} missing in {config}"))
    };
    println!(
        "cargo:rustc-env=IVY_UPSTREAM_VERSION={}.{}",
        value("IVY_UPSTREAM_MARKETING_VERSION"),
        value("IVY_UPSTREAM_BUILD_NUMBER")
    );
}
