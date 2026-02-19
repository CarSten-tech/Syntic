//! Platform-independent Syntic core runtime primitives.

pub mod command;
pub mod dictation;
pub mod domain;
pub mod events;
mod runtime;
pub mod session_history;
pub mod stt;

pub use runtime::{CORE_VERSION, CoreRuntime, HealthSnapshot};
