//! Checks that the core can read a copy of the Swift app's database:
//! cargo run -p ivy-core --example legacy_check -- <copy of signal.sqlite> <96 hex digits of the key spec>

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let [_, path, key] = args.as_slice() else {
        eprintln!("usage: legacy_check <signal.sqlite> <key spec as hex>");
        std::process::exit(2);
    };
    let key = hex::decode(key).expect("key spec must be hex");
    match ivy_core::legacy_summary(path.clone(), key) {
        Ok(summary) => println!("{summary:#?}"),
        Err(e) => {
            eprintln!("cannot read: {e}");
            std::process::exit(1);
        }
    }
}
