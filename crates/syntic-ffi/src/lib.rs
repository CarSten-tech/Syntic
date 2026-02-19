//! C ABI bridge for embedding `syntic-core` into platform-specific shells.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;
use std::sync::{Mutex, OnceLock};

use syntic_core::CoreRuntime;
use syntic_core::command::{evaluate_safety, fallback_classify};
use syntic_core::dictation::DictationTransitionError;

static CORE_RUNTIME: OnceLock<Mutex<CoreRuntime>> = OnceLock::new();
const CORE_VERSION_CSTR: &[u8] = concat!(env!("CARGO_PKG_VERSION"), "\0").as_bytes();

#[repr(u8)]
enum FfiStatusCode {
    Success = 0,
    SessionAlreadyActive = 10,
    DictationNotListening = 11,
    DictationNotReviewing = 12,
    DictationNotActive = 13,
    NullPointer = 20,
    InvalidUtf8 = 21,
    Internal = 255,
}

fn runtime_mutex() -> &'static Mutex<CoreRuntime> {
    CORE_RUNTIME.get_or_init(|| Mutex::new(CoreRuntime::new()))
}

fn map_transition_error(error: DictationTransitionError) -> FfiStatusCode {
    match error {
        DictationTransitionError::SessionAlreadyActive => FfiStatusCode::SessionAlreadyActive,
        DictationTransitionError::DictationNotListening => FfiStatusCode::DictationNotListening,
        DictationTransitionError::DictationNotReviewing => FfiStatusCode::DictationNotReviewing,
        DictationTransitionError::DictationNotActive => FfiStatusCode::DictationNotActive,
    }
}

fn with_runtime_mut<F>(operation: F) -> FfiStatusCode
where
    F: FnOnce(&mut CoreRuntime) -> Result<(), DictationTransitionError>,
{
    let Ok(mut runtime) = runtime_mutex().lock() else {
        return FfiStatusCode::Internal;
    };

    match operation(&mut runtime) {
        Ok(()) => FfiStatusCode::Success,
        Err(error) => map_transition_error(error),
    }
}

fn with_runtime<F>(operation: F) -> Result<String, FfiStatusCode>
where
    F: FnOnce(&CoreRuntime) -> String,
{
    let runtime = runtime_mutex()
        .lock()
        .map_err(|_| FfiStatusCode::Internal)?;
    Ok(operation(&runtime))
}

fn parse_utf8_input(pointer: *const c_char) -> Result<String, FfiStatusCode> {
    if pointer.is_null() {
        return Err(FfiStatusCode::NullPointer);
    }

    // SAFETY: pointer is checked for null and required to refer to a NUL-terminated C string.
    let text = unsafe { CStr::from_ptr(pointer) };
    let value = text.to_str().map_err(|_| FfiStatusCode::InvalidUtf8)?;
    Ok(value.to_owned())
}

fn json_escape(value: &str) -> String {
    let mut escaped = String::with_capacity(value.len());
    for ch in value.chars() {
        match ch {
            '\\' => escaped.push_str("\\\\"),
            '"' => escaped.push_str("\\\""),
            '\n' => escaped.push_str("\\n"),
            '\r' => escaped.push_str("\\r"),
            '\t' => escaped.push_str("\\t"),
            '\u{8}' => escaped.push_str("\\b"),
            '\u{c}' => escaped.push_str("\\f"),
            '\0' => escaped.push_str("\\u0000"),
            other => escaped.push(other),
        }
    }

    escaped
}

fn to_heap_c_string(payload: String) -> *mut c_char {
    match CString::new(payload) {
        Ok(value) => value.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

fn dictation_snapshot_json(runtime: &CoreRuntime) -> String {
    let snapshot = runtime.dictation_session().snapshot();
    let last_error = snapshot.last_error.as_deref().map_or_else(
        || "null".to_owned(),
        |value| format!("\"{}\"", json_escape(value)),
    );

    format!(
        "{{\"phase\":\"{}\",\"live_transcript\":\"{}\",\"review_transcript\":\"{}\",\"last_error\":{},\"requires_confirmation\":{}}}",
        snapshot.phase.as_str(),
        json_escape(&snapshot.live_transcript),
        json_escape(&snapshot.review_transcript),
        last_error,
        snapshot.requires_confirmation
    )
}

fn command_intent_json(utterance: &str) -> String {
    let intent = fallback_classify(utterance);
    format!(
        "{{\"kind\":\"{}\",\"summary\":\"{}\",\"confidence_percent\":{},\"requires_confirmation\":{}}}",
        intent.kind.as_str(),
        json_escape(&intent.summary),
        intent.confidence_percent,
        intent.requires_confirmation
    )
}

fn command_safety_json(utterance: &str) -> String {
    let intent = fallback_classify(utterance);
    let safety = evaluate_safety(&intent);
    format!(
        "{{\"decision\":\"{}\",\"destructive\":{},\"reason\":\"{}\"}}",
        safety.decision.as_str(),
        safety.destructive,
        safety.reason
    )
}

/// Returns a pointer to a static NUL-terminated UTF-8 version string.
///
/// The returned pointer must not be freed by the caller.
#[unsafe(no_mangle)]
pub extern "C" fn syntic_core_version() -> *const c_char {
    CORE_VERSION_CSTR.as_ptr().cast::<c_char>()
}

/// Returns a heap-allocated JSON string with core health metadata.
///
/// The caller owns the returned pointer and must release it using
/// `syntic_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn syntic_runtime_health_json() -> *mut c_char {
    let payload = with_runtime(|runtime| {
        let snapshot = runtime.health_snapshot();
        format!(
            "{{\"service_name\":\"{}\",\"version\":\"{}\",\"status\":\"{}\"}}",
            snapshot.service_name, snapshot.version, snapshot.status
        )
    });

    match payload {
        Ok(json) => to_heap_c_string(json),
        Err(_) => ptr::null_mut(),
    }
}

/// Returns a heap-allocated JSON string with the current dictation state.
///
/// The caller owns the returned pointer and must release it using
/// `syntic_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn syntic_dictation_state_json() -> *mut c_char {
    let payload = with_runtime(dictation_snapshot_json);
    match payload {
        Ok(json) => to_heap_c_string(json),
        Err(_) => ptr::null_mut(),
    }
}

/// Classifies a command utterance using fallback intent detection.
///
/// The caller owns the returned pointer and must release it using
/// `syntic_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn syntic_command_classify_json(utterance: *const c_char) -> *mut c_char {
    let Ok(text) = parse_utf8_input(utterance) else {
        return ptr::null_mut();
    };

    to_heap_c_string(command_intent_json(&text))
}

/// Evaluates command safety requirements for a given utterance.
///
/// The caller owns the returned pointer and must release it using
/// `syntic_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn syntic_command_safety_json(utterance: *const c_char) -> *mut c_char {
    let Ok(text) = parse_utf8_input(utterance) else {
        return ptr::null_mut();
    };

    to_heap_c_string(command_safety_json(&text))
}

/// Resets dictation state to `idle`.
///
/// Returns a numeric FFI status code.
#[unsafe(no_mangle)]
pub extern "C" fn syntic_dictation_reset() -> u8 {
    let Ok(mut runtime) = runtime_mutex().lock() else {
        return FfiStatusCode::Internal as u8;
    };

    runtime.dictation_session_mut().reset();
    FfiStatusCode::Success as u8
}

/// Starts a dictation session.
///
/// Returns a numeric FFI status code.
#[unsafe(no_mangle)]
pub extern "C" fn syntic_dictation_start() -> u8 {
    with_runtime_mut(|runtime| runtime.dictation_session_mut().start_listening()) as u8
}

/// Updates live transcription text while dictation is listening.
///
/// Returns a numeric FFI status code.
#[unsafe(no_mangle)]
pub extern "C" fn syntic_dictation_append_partial(text: *const c_char) -> u8 {
    let transcript = match parse_utf8_input(text) {
        Ok(value) => value,
        Err(error) => return error as u8,
    };

    with_runtime_mut(|runtime| runtime.dictation_session_mut().append_partial(&transcript)) as u8
}

/// Finalizes dictation and moves it to review state.
///
/// Returns a numeric FFI status code.
#[unsafe(no_mangle)]
pub extern "C" fn syntic_dictation_finalize_review(text: *const c_char) -> u8 {
    let transcript = match parse_utf8_input(text) {
        Ok(value) => value,
        Err(error) => return error as u8,
    };

    with_runtime_mut(|runtime| runtime.dictation_session_mut().finalize_review(&transcript)) as u8
}

/// Confirms the reviewed dictation text.
///
/// Returns a numeric FFI status code.
#[unsafe(no_mangle)]
pub extern "C" fn syntic_dictation_confirm() -> u8 {
    with_runtime_mut(|runtime| runtime.dictation_session_mut().confirm()) as u8
}

/// Cancels the current dictation session.
///
/// Returns a numeric FFI status code.
#[unsafe(no_mangle)]
pub extern "C" fn syntic_dictation_cancel() -> u8 {
    with_runtime_mut(|runtime| runtime.dictation_session_mut().cancel()) as u8
}

/// Moves dictation state to `failed` and sets an error message.
///
/// Returns a numeric FFI status code.
#[unsafe(no_mangle)]
pub extern "C" fn syntic_dictation_fail(message: *const c_char) -> u8 {
    let failure_message = match parse_utf8_input(message) {
        Ok(value) => value,
        Err(error) => return error as u8,
    };

    let Ok(mut runtime) = runtime_mutex().lock() else {
        return FfiStatusCode::Internal as u8;
    };

    runtime.dictation_session_mut().fail(&failure_message);
    FfiStatusCode::Success as u8
}

/// Frees strings created by FFI JSON functions.
///
/// # Safety
///
/// `pointer` must have been allocated by `CString::into_raw` in this library.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn syntic_string_free(pointer: *mut c_char) {
    if pointer.is_null() {
        return;
    }

    // SAFETY: caller contract guarantees provenance from `CString::into_raw`.
    unsafe {
        drop(CString::from_raw(pointer));
    }
}

#[cfg(test)]
mod tests {
    use std::ffi::{CStr, CString};
    use std::ptr;

    use super::{
        syntic_command_classify_json, syntic_command_safety_json, syntic_core_version,
        syntic_dictation_append_partial, syntic_dictation_confirm,
        syntic_dictation_finalize_review, syntic_dictation_reset, syntic_dictation_start,
        syntic_dictation_state_json, syntic_runtime_health_json, syntic_string_free,
    };

    #[test]
    fn core_version_pointer_is_valid_utf8() {
        let version_pointer = syntic_core_version();
        assert!(!version_pointer.is_null());

        // SAFETY: `syntic_core_version` returns a static C string pointer.
        let version = unsafe { CStr::from_ptr(version_pointer) };
        assert!(!version.to_str().expect("utf8").is_empty());
    }

    #[test]
    fn health_json_can_be_freed() {
        let payload_pointer = syntic_runtime_health_json();
        assert!(!payload_pointer.is_null());

        // SAFETY: pointer returned by `syntic_runtime_health_json` is valid C string.
        let payload = unsafe { CStr::from_ptr(payload_pointer) };
        let payload_text = payload.to_str().expect("utf8");
        assert!(payload_text.contains("\"service_name\":\"syntic-core\""));

        // SAFETY: `payload_pointer` came from `syntic_runtime_health_json`.
        unsafe { syntic_string_free(payload_pointer) };
    }

    #[test]
    fn dictation_happy_path_transitions_to_confirmed() {
        assert_eq!(syntic_dictation_reset(), 0);
        assert_eq!(syntic_dictation_start(), 0);

        let partial = CString::new("hello").expect("cstring");
        assert_eq!(syntic_dictation_append_partial(partial.as_ptr()), 0);

        let review = CString::new("hello world").expect("cstring");
        assert_eq!(syntic_dictation_finalize_review(review.as_ptr()), 0);
        assert_eq!(syntic_dictation_confirm(), 0);

        let state_pointer = syntic_dictation_state_json();
        assert!(!state_pointer.is_null());

        // SAFETY: pointer returned by `syntic_dictation_state_json` is a valid C string.
        let payload = unsafe { CStr::from_ptr(state_pointer) };
        let payload_text = payload.to_str().expect("utf8");
        assert!(payload_text.contains("\"phase\":\"confirmed\""));

        // SAFETY: `state_pointer` came from `syntic_dictation_state_json`.
        unsafe { syntic_string_free(state_pointer) };
    }

    #[test]
    fn dictation_start_twice_returns_transition_error_status() {
        assert_eq!(syntic_dictation_reset(), 0);
        assert_eq!(syntic_dictation_start(), 0);
        assert_eq!(syntic_dictation_start(), 10);
    }

    #[test]
    fn append_partial_with_null_pointer_returns_null_status() {
        assert_eq!(syntic_dictation_reset(), 0);
        assert_eq!(syntic_dictation_start(), 0);
        assert_eq!(syntic_dictation_append_partial(ptr::null()), 20);
    }

    #[test]
    fn command_classification_json_contains_timer_kind() {
        let utterance = CString::new("Stelle einen Timer auf 20min").expect("cstring");
        let payload_pointer = syntic_command_classify_json(utterance.as_ptr());
        assert!(!payload_pointer.is_null());

        // SAFETY: pointer returned by `syntic_command_classify_json` is a valid C string.
        let payload = unsafe { CStr::from_ptr(payload_pointer) };
        let payload_text = payload.to_str().expect("utf8");
        assert!(payload_text.contains("\"kind\":\"set_timer\""));

        // SAFETY: `payload_pointer` came from `syntic_command_classify_json`.
        unsafe { syntic_string_free(payload_pointer) };
    }

    #[test]
    fn command_safety_json_marks_rename_as_destructive() {
        let utterance = CString::new("rename file report to final").expect("cstring");
        let payload_pointer = syntic_command_safety_json(utterance.as_ptr());
        assert!(!payload_pointer.is_null());

        // SAFETY: pointer returned by `syntic_command_safety_json` is a valid C string.
        let payload = unsafe { CStr::from_ptr(payload_pointer) };
        let payload_text = payload.to_str().expect("utf8");
        assert!(payload_text.contains("\"destructive\":true"));

        // SAFETY: `payload_pointer` came from `syntic_command_safety_json`.
        unsafe { syntic_string_free(payload_pointer) };
    }
}
