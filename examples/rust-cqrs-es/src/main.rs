// Bank Account Service — Rust CQRS + Event Sourcing example.
//
// Wiring corresponds to: compose BankAccountWiring
//   bind AccountRepository  -> PostgresAccountRepo    (here: InMemoryAccountRepo)
//   bind EventStore         -> PostgresEventStore     (here: InMemoryEventStore)
//   bind StatementStore     -> PostgresStatementStore (here: InMemoryStatementStore)

mod domain;
mod command;
mod query;
mod infrastructure;

use domain::account::Money;
use infrastructure::{InMemoryAccountRepo, InMemoryEventStore, InMemoryStatementStore};

fn main() {
    println!("=== Rust CQRS + Event Sourcing: Bank Account Service ===\n");

    // --- Wiring: bind adapters ---
    let mut repo = InMemoryAccountRepo::default();
    let mut events = InMemoryEventStore::default();
    let statements = InMemoryStatementStore::default();

    // --- Commands ---

    let alice_id = command::open_account::execute(&mut repo, &mut events, "Alice")
        .expect("open Alice");
    let bob_id = command::open_account::execute(&mut repo, &mut events, "Bob")
        .expect("open Bob");
    println!("Opened: {} (Alice), {} (Bob)", alice_id, bob_id);

    let balance = command::deposit_money::execute(
        &mut repo, &mut events, &alice_id, Money::new(1000.0, "USD"),
    ).expect("deposit to Alice");
    println!("Deposit to Alice: balance = {}", balance);

    let balance = command::deposit_money::execute(
        &mut repo, &mut events, &bob_id, Money::new(500.0, "USD"),
    ).expect("deposit to Bob");
    println!("Deposit to Bob: balance = {}", balance);

    command::transfer_money::execute(
        &mut repo, &mut events, &alice_id, &bob_id, Money::new(250.0, "USD"),
    ).expect("transfer Alice -> Bob");
    println!("Transfer: Alice -> Bob 250.00 USD");

    // --- Queries ---

    let alice_bal = query::get_balance::execute(&repo, &alice_id)
        .expect("get Alice balance");
    let bob_bal = query::get_balance::execute(&repo, &bob_id)
        .expect("get Bob balance");
    println!("\nBalances:");
    println!("  Alice: {}", alice_bal);
    println!("  Bob:   {}", bob_bal);

    let alice_events = query::get_history::execute(&events, &alice_id)
        .expect("get Alice history");
    println!("\nAlice event history ({} events):", alice_events.len());
    for e in &alice_events {
        println!("  - {}", e.event_type());
    }

    // --- Guard verification ---

    // Insufficient funds
    match command::withdraw_money::execute(
        &mut repo, &mut events, &alice_id, Money::new(9999.0, "USD"),
    ) {
        Ok(_) => println!("\nWithdraw succeeded (unexpected)"),
        Err(e) => println!("\nGuard: withdraw 9999 from Alice -> {}", e),
    }

    // Same account transfer
    match command::transfer_money::execute(
        &mut repo, &mut events, &alice_id, &alice_id, Money::new(1.0, "USD"),
    ) {
        Ok(_) => println!("Self-transfer succeeded (unexpected)"),
        Err(e) => println!("Guard: self-transfer -> {}", e),
    }

    // Non-positive amount
    match command::transfer_money::execute(
        &mut repo, &mut events, &alice_id, &bob_id, Money::new(0.0, "USD"),
    ) {
        Ok(_) => println!("Zero transfer succeeded (unexpected)"),
        Err(e) => println!("Guard: zero transfer -> {}", e),
    }

    // --- Account lifecycle ---

    // Freeze Bob's account
    command::freeze_account::execute(&mut repo, &mut events, &bob_id, "suspicious activity")
        .expect("freeze Bob");
    println!("\nFroze Bob's account");

    // Attempt to freeze again (should fail)
    match command::freeze_account::execute(&mut repo, &mut events, &bob_id, "double freeze") {
        Ok(_) => println!("Double freeze succeeded (unexpected)"),
        Err(e) => println!("Guard: double freeze -> {}", e),
    }

    // Unfreeze Bob's account
    command::unfreeze_account::execute(&mut repo, &mut events, &bob_id)
        .expect("unfreeze Bob");
    println!("Unfroze Bob's account");

    // Close Alice's account
    command::close_account::execute(&mut repo, &mut events, &alice_id, "customer request")
        .expect("close Alice");
    println!("Closed Alice's account");

    // Attempt to close again (should fail)
    match command::close_account::execute(&mut repo, &mut events, &alice_id, "retry") {
        Ok(_) => println!("Double close succeeded (unexpected)"),
        Err(e) => println!("Guard: double close -> {}", e),
    }

    // --- List accounts ---

    let all_accounts = query::list_accounts::execute(&repo)
        .expect("list accounts");
    println!("\nAll accounts ({}):", all_accounts.len());
    for a in &all_accounts {
        println!("  - {} (owner: {}, status: {}, balance: {})", a.id, a.owner, a.status, a.balance);
    }

    // --- Statements ---

    let alice_stmts = query::get_statement::execute(&events, &statements, &alice_id)
        .expect("get Alice statements");
    println!("\nAlice statements: {} (none generated yet)", alice_stmts.len());

    // --- Final event history ---

    let bob_events = query::get_history::execute(&events, &bob_id)
        .expect("get Bob history");
    println!("\nBob event history ({} events):", bob_events.len());
    for e in &bob_events {
        println!("  - {}", e.event_type());
    }
}
