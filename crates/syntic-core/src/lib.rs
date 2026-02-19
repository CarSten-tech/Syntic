//! Platform-independent Syntic core runtime primitives.

pub mod command;
pub mod dictation;
mod runtime;

pub use runtime::{CORE_VERSION, CoreRuntime, HealthSnapshot};
