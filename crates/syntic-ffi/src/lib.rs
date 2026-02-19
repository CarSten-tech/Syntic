//! C ABI bridge for embedding `syntic-core` into platform-specific shells.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;
use std::sync::{Mutex, OnceLock};

use syntic_core::CoreRuntime;
use syntic_core::command::{evaluate_safety, fallback_classify};
use syntic_core::dictation::{DictationPhase, DictationTransitionError};
use syntic_core::domain::{DomainEvent, DomainEventPayload, ToolRuntimeSignal};
use syntic_core::events::{CoreEvent, CoreEventPayload};
use syntic_core::session_history::{
    SessionHistoryRecord, SessionHistoryRecordInput, SessionInjectionDisposition, SessionOutcome,
};
use syntic_core::stt::{SttPreferenceMode, SttRoutingInput, select_provider};

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
    InvalidArgument = 22,
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

fn with_runtime_mut<F>(operation_name: &str, operation: F) -> FfiStatusCode
where
    F: FnOnce(&mut CoreRuntime) -> Result<(), DictationTransitionError>,
{
    let Ok(mut runtime) = runtime_mutex().lock() else {
        return FfiStatusCode::Internal;
    };

    match operation(&mut runtime) {
        Ok(()) => FfiStatusCode::Success,
        Err(error) => {
            runtime.record_error_event(
                "ffi.dictation",
                error.as_str(),
                &format!(
                    "Dictation transition failed in `{}`: {}",
                    operation_name,
                    error.as_str()
                ),
            );
            map_transition_error(error)
        }
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

fn parse_utf8_optional_input(pointer: *const c_char) -> Result<String, FfiStatusCode> {
    if pointer.is_null() {
        return Ok(String::new());
    }
    parse_utf8_input(pointer)
}

fn none_if_empty(value: String) -> Option<String> {
    if value.trim().is_empty() {
        None
    } else {
        Some(value)
    }
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
    let move_destination_json = intent.arguments.move_destination.as_deref().map_or_else(
        || "null".to_owned(),
        |value| format!("\"{}\"", json_escape(value)),
    );
    let move_destination_kind_json = intent.arguments.move_destination_kind.map_or_else(
        || "null".to_owned(),
        |kind| format!("\"{}\"", kind.as_str()),
    );
    let rename_target_json = intent.arguments.rename_target.as_deref().map_or_else(
        || "null".to_owned(),
        |value| format!("\"{}\"", json_escape(value)),
    );
    let timer_duration_json = intent.arguments.timer_duration.as_deref().map_or_else(
        || "null".to_owned(),
        |value| format!("\"{}\"", json_escape(value)),
    );

    format!(
        "{{\"kind\":\"{}\",\"summary\":\"{}\",\"confidence_percent\":{},\"requires_confirmation\":{},\"arguments\":{{\"move_destination\":{},\"move_destination_kind\":{},\"rename_target\":{},\"timer_duration\":{}}}}}",
        intent.kind.as_str(),
        json_escape(&intent.summary),
        intent.confidence_percent,
        intent.requires_confirmation,
        move_destination_json,
        move_destination_kind_json,
        rename_target_json,
        timer_duration_json
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

fn parse_stt_preference_mode(raw_value: u8) -> Option<SttPreferenceMode> {
    match raw_value {
        0 => Some(SttPreferenceMode::LocalOnly),
        1 => Some(SttPreferenceMode::CloudOnly),
        2 => Some(SttPreferenceMode::Auto),
        _ => None,
    }
}

fn normalized_event_limit(raw_limit: u16) -> usize {
    if raw_limit == 0 {
        return 50;
    }
    (raw_limit as usize).min(256)
}

fn parse_session_outcome(value: &str) -> Option<SessionOutcome> {
    SessionOutcome::parse(value.trim().to_lowercase().as_str())
}

fn parse_injection_disposition(value: &str) -> Option<SessionInjectionDisposition> {
    SessionInjectionDisposition::parse(value.trim().to_lowercase().as_str())
}

fn core_event_json(event: &CoreEvent) -> String {
    match &event.payload {
        CoreEventPayload::Error { code, message } => format!(
            "{{\"id\":{},\"timestamp_ms\":{},\"kind\":\"{}\",\"severity\":\"{}\",\"source\":\"{}\",\"code\":\"{}\",\"message\":\"{}\"}}",
            event.id,
            event.timestamp_ms,
            event.kind.as_str(),
            event.severity.as_str(),
            json_escape(&event.source),
            json_escape(code),
            json_escape(message)
        ),
        CoreEventPayload::Permission {
            permission,
            status,
            detail,
        } => format!(
            "{{\"id\":{},\"timestamp_ms\":{},\"kind\":\"{}\",\"severity\":\"{}\",\"source\":\"{}\",\"permission\":\"{}\",\"status\":\"{}\",\"detail\":\"{}\"}}",
            event.id,
            event.timestamp_ms,
            event.kind.as_str(),
            event.severity.as_str(),
            json_escape(&event.source),
            json_escape(permission),
            json_escape(status),
            json_escape(detail)
        ),
        CoreEventPayload::Telemetry {
            category,
            action,
            status,
            context_json,
            value_ms,
        } => {
            let value_ms_json = value_ms
                .map(|value| value.to_string())
                .unwrap_or_else(|| "null".to_owned());
            format!(
                "{{\"id\":{},\"timestamp_ms\":{},\"kind\":\"{}\",\"severity\":\"{}\",\"source\":\"{}\",\"category\":\"{}\",\"action\":\"{}\",\"status\":\"{}\",\"context_json\":\"{}\",\"value_ms\":{}}}",
                event.id,
                event.timestamp_ms,
                event.kind.as_str(),
                event.severity.as_str(),
                json_escape(&event.source),
                json_escape(category),
                json_escape(action),
                json_escape(status),
                json_escape(context_json),
                value_ms_json
            )
        }
    }
}

fn core_events_payload_json(events: &[CoreEvent]) -> String {
    let serialized_events = events
        .iter()
        .map(core_event_json)
        .collect::<Vec<_>>()
        .join(",");
    format!("{{\"events\":[{serialized_events}]}}")
}

fn domain_event_json(event: &DomainEvent) -> String {
    match &event.payload {
        DomainEventPayload::DictationReviewCancelled {
            source,
            phase_before,
            review_transcript_length,
        }
        | DomainEventPayload::DictationReviewConfirmed {
            source,
            phase_before,
            review_transcript_length,
        } => format!(
            "{{\"id\":{},\"timestamp_ms\":{},\"name\":\"{}\",\"source\":\"{}\",\"phase_before\":\"{}\",\"review_transcript_length\":{}}}",
            event.id,
            event.timestamp_ms,
            event.name.as_str(),
            json_escape(source),
            json_escape(phase_before),
            review_transcript_length
        ),
    }
}

fn domain_events_payload_json(events: &[DomainEvent]) -> String {
    let serialized_events = events
        .iter()
        .map(domain_event_json)
        .collect::<Vec<_>>()
        .join(",");
    format!("{{\"events\":[{serialized_events}]}}")
}

fn tool_runtime_signal_json(signal: &ToolRuntimeSignal) -> String {
    format!(
        "{{\"id\":{},\"timestamp_ms\":{},\"action\":\"{}\",\"reason\":\"{}\",\"origin_domain_event_id\":{}}}",
        signal.id,
        signal.timestamp_ms,
        signal.action.as_str(),
        json_escape(&signal.reason),
        signal.origin_domain_event_id
    )
}

fn tool_runtime_signals_payload_json(signals: &[ToolRuntimeSignal]) -> String {
    let serialized_signals = signals
        .iter()
        .map(tool_runtime_signal_json)
        .collect::<Vec<_>>()
        .join(",");
    format!("{{\"signals\":[{serialized_signals}]}}")
}

fn session_history_record_json(record: &SessionHistoryRecord) -> String {
    let duration_ms_json = record
        .duration_ms
        .map_or_else(|| "null".to_owned(), |value| value.to_string());
    let error_code_json = record.error_code.as_deref().map_or_else(
        || "null".to_owned(),
        |value| format!("\"{}\"", json_escape(value)),
    );
    let injection_disposition_json = record.injection_disposition.map_or_else(
        || "null".to_owned(),
        |value| format!("\"{}\"", value.as_str()),
    );
    let undone_at_ms_json = record
        .undone_at_ms
        .map_or_else(|| "null".to_owned(), |value| value.to_string());

    format!(
        "{{\"id\":{},\"created_at_ms\":{},\"duration_ms\":{},\"locale\":\"{}\",\"route_provider\":\"{}\",\"outcome\":\"{}\",\"transcript\":\"{}\",\"error_code\":{},\"injection_disposition\":{},\"undone_at_ms\":{}}}",
        record.id,
        record.created_at_ms,
        duration_ms_json,
        json_escape(&record.locale),
        json_escape(&record.route_provider),
        record.outcome.as_str(),
        json_escape(&record.transcript),
        error_code_json,
        injection_disposition_json,
        undone_at_ms_json
    )
}

fn session_history_payload_json(records: &[SessionHistoryRecord]) -> String {
    let serialized_records = records
        .iter()
        .map(session_history_record_json)
        .collect::<Vec<_>>()
        .join(",");
    format!("{{\"records\":[{serialized_records}]}}")
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

/// Computes STT routing decision from runtime constraints.
///
/// `preference_mode` mapping:
/// - `0`: local only
/// - `1`: cloud only
/// - `2`: auto
///
/// The caller owns the returned pointer and must release it using
/// `syntic_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn syntic_stt_route_json(
    preference_mode: u8,
    sensitive_mode_enabled: u8,
    network_available: u8,
    utterance_duration_ms: u32,
) -> *mut c_char {
    let Some(mode) = parse_stt_preference_mode(preference_mode) else {
        return ptr::null_mut();
    };

    let decision = select_provider(SttRoutingInput {
        preference_mode: mode,
        sensitive_mode_enabled: sensitive_mode_enabled != 0,
        network_available: network_available != 0,
        utterance_duration_ms,
    });

    let payload = format!(
        "{{\"provider\":\"{}\",\"reason\":\"{}\"}}",
        decision.provider.as_str(),
        decision.reason
    );

    to_heap_c_string(payload)
}

/// Emits an error event into the core event journal.
///
/// Returns a numeric FFI status code.
#[unsafe(no_mangle)]
pub extern "C" fn syntic_core_event_report_error(
    source: *const c_char,
    code: *const c_char,
    message: *const c_char,
) -> u8 {
    let source = match parse_utf8_input(source) {
        Ok(value) => value,
        Err(error) => return error as u8,
    };
    let code = match parse_utf8_input(code) {
        Ok(value) => value,
        Err(error) => return error as u8,
    };
    let message = match parse_utf8_input(message) {
        Ok(value) => value,
        Err(error) => return error as u8,
    };

    let Ok(mut runtime) = runtime_mutex().lock() else {
        return FfiStatusCode::Internal as u8;
    };

    runtime.record_error_event(&source, &code, &message);
    FfiStatusCode::Success as u8
}

/// Emits a permission event into the core event journal.
///
/// `detail` is optional and may be null.
///
/// Returns a numeric FFI status code.
#[unsafe(no_mangle)]
pub extern "C" fn syntic_core_event_report_permission(
    source: *const c_char,
    permission: *const c_char,
    status: *const c_char,
    detail: *const c_char,
) -> u8 {
    let source = match parse_utf8_input(source) {
        Ok(value) => value,
        Err(error) => return error as u8,
    };
    let permission = match parse_utf8_input(permission) {
        Ok(value) => value,
        Err(error) => return error as u8,
    };
    let status = match parse_utf8_input(status) {
        Ok(value) => value,
        Err(error) => return error as u8,
    };
    let detail = match parse_utf8_optional_input(detail) {
        Ok(value) => value,
        Err(error) => return error as u8,
    };

    let Ok(mut runtime) = runtime_mutex().lock() else {
        return FfiStatusCode::Internal as u8;
    };

    runtime.record_permission_event(&source, &permission, &status, &detail);
    FfiStatusCode::Success as u8
}

/// Emits a telemetry event into the core event journal.
///
/// `context_json` is optional and may be null.
///
/// Returns a numeric FFI status code.
#[unsafe(no_mangle)]
pub extern "C" fn syntic_core_event_report_telemetry(
    source: *const c_char,
    category: *const c_char,
    action: *const c_char,
    status: *const c_char,
    context_json: *const c_char,
    value_ms: u32,
) -> u8 {
    let source = match parse_utf8_input(source) {
        Ok(value) => value,
        Err(error) => return error as u8,
    };
    let category = match parse_utf8_input(category) {
        Ok(value) => value,
        Err(error) => return error as u8,
    };
    let action = match parse_utf8_input(action) {
        Ok(value) => value,
        Err(error) => return error as u8,
    };
    let status = match parse_utf8_input(status) {
        Ok(value) => value,
        Err(error) => return error as u8,
    };
    let context_json = match parse_utf8_optional_input(context_json) {
        Ok(value) => value,
        Err(error) => return error as u8,
    };

    let Ok(mut runtime) = runtime_mutex().lock() else {
        return FfiStatusCode::Internal as u8;
    };

    runtime.record_telemetry_event(
        &source,
        &category,
        &action,
        &status,
        &context_json,
        if value_ms == 0 { None } else { Some(value_ms) },
    );
    FfiStatusCode::Success as u8
}

/// Returns a heap-allocated JSON string with core events after the given ID.
///
/// The caller owns the returned pointer and must release it using
/// `syntic_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn syntic_core_events_since_json(
    last_seen_event_id: u64,
    limit: u16,
) -> *mut c_char {
    let payload = with_runtime(|runtime| {
        let events = runtime.core_events_since(last_seen_event_id, normalized_event_limit(limit));
        core_events_payload_json(&events)
    });

    match payload {
        Ok(json) => to_heap_c_string(json),
        Err(_) => ptr::null_mut(),
    }
}

/// Clears the in-memory core event journal.
///
/// Returns a numeric FFI status code.
#[unsafe(no_mangle)]
pub extern "C" fn syntic_core_events_clear() -> u8 {
    let Ok(mut runtime) = runtime_mutex().lock() else {
        return FfiStatusCode::Internal as u8;
    };

    runtime.clear_core_events();
    FfiStatusCode::Success as u8
}

/// Returns a heap-allocated JSON string with domain events after the given ID.
///
/// The caller owns the returned pointer and must release it using
/// `syntic_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn syntic_domain_events_since_json(
    last_seen_event_id: u64,
    limit: u16,
) -> *mut c_char {
    let payload = with_runtime(|runtime| {
        let events = runtime.domain_events_since(last_seen_event_id, normalized_event_limit(limit));
        domain_events_payload_json(&events)
    });

    match payload {
        Ok(json) => to_heap_c_string(json),
        Err(_) => ptr::null_mut(),
    }
}

/// Returns a heap-allocated JSON string with tool-runtime signals after the given ID.
///
/// The caller owns the returned pointer and must release it using
/// `syntic_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn syntic_tool_runtime_signals_since_json(
    last_seen_signal_id: u64,
    limit: u16,
) -> *mut c_char {
    let payload = with_runtime(|runtime| {
        let signals =
            runtime.tool_runtime_signals_since(last_seen_signal_id, normalized_event_limit(limit));
        tool_runtime_signals_payload_json(&signals)
    });

    match payload {
        Ok(json) => to_heap_c_string(json),
        Err(_) => ptr::null_mut(),
    }
}

/// Clears in-memory domain events and tool-runtime signals.
///
/// Returns a numeric FFI status code.
#[unsafe(no_mangle)]
pub extern "C" fn syntic_domain_events_clear() -> u8 {
    let Ok(mut runtime) = runtime_mutex().lock() else {
        return FfiStatusCode::Internal as u8;
    };

    runtime.clear_domain_events();
    FfiStatusCode::Success as u8
}

/// Persists one session-history entry into the core runtime journal.
///
/// Optional fields (`error_code`, `injection_disposition`) may be null.
/// `duration_ms=0` is treated as missing duration.
#[unsafe(no_mangle)]
pub extern "C" fn syntic_session_history_record(
    outcome: *const c_char,
    transcript: *const c_char,
    locale: *const c_char,
    route_provider: *const c_char,
    duration_ms: u32,
    error_code: *const c_char,
    injection_disposition: *const c_char,
) -> u8 {
    let outcome_raw = match parse_utf8_input(outcome) {
        Ok(value) => value,
        Err(error) => return error as u8,
    };
    let Some(parsed_outcome) = parse_session_outcome(&outcome_raw) else {
        return FfiStatusCode::InvalidArgument as u8;
    };
    let transcript = match parse_utf8_input(transcript) {
        Ok(value) => value,
        Err(error) => return error as u8,
    };
    let locale = match parse_utf8_input(locale) {
        Ok(value) => value,
        Err(error) => return error as u8,
    };
    let route_provider = match parse_utf8_input(route_provider) {
        Ok(value) => value,
        Err(error) => return error as u8,
    };

    let error_code = match parse_utf8_optional_input(error_code) {
        Ok(value) => none_if_empty(value),
        Err(error) => return error as u8,
    };
    let injection_disposition = match parse_utf8_optional_input(injection_disposition) {
        Ok(value) => match none_if_empty(value) {
            None => None,
            Some(normalized) => {
                let Some(parsed) = parse_injection_disposition(&normalized) else {
                    return FfiStatusCode::InvalidArgument as u8;
                };
                Some(parsed)
            }
        },
        Err(error) => return error as u8,
    };

    let Ok(mut runtime) = runtime_mutex().lock() else {
        return FfiStatusCode::Internal as u8;
    };

    runtime.record_session_history_entry(&SessionHistoryRecordInput {
        duration_ms: if duration_ms == 0 {
            None
        } else {
            Some(duration_ms)
        },
        locale: &locale,
        route_provider: &route_provider,
        outcome: parsed_outcome,
        transcript: &transcript,
        error_code: error_code.as_deref(),
        injection_disposition,
    });
    FfiStatusCode::Success as u8
}

/// Marks the latest confirmed session-history record as undone, if available.
#[unsafe(no_mangle)]
pub extern "C" fn syntic_session_history_mark_last_confirmed_undone() -> u8 {
    let Ok(mut runtime) = runtime_mutex().lock() else {
        return FfiStatusCode::Internal as u8;
    };

    runtime.mark_last_confirmed_session_as_undone();
    FfiStatusCode::Success as u8
}

/// Returns a heap-allocated JSON string with session-history records after the given ID.
///
/// The caller owns the returned pointer and must release it using
/// `syntic_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn syntic_session_history_since_json(
    last_seen_record_id: u64,
    limit: u16,
) -> *mut c_char {
    let payload = with_runtime(|runtime| {
        let records =
            runtime.session_history_since(last_seen_record_id, normalized_event_limit(limit));
        session_history_payload_json(&records)
    });

    match payload {
        Ok(json) => to_heap_c_string(json),
        Err(_) => ptr::null_mut(),
    }
}

/// Clears the core runtime session-history journal.
///
/// Returns a numeric FFI status code.
#[unsafe(no_mangle)]
pub extern "C" fn syntic_session_history_clear() -> u8 {
    let Ok(mut runtime) = runtime_mutex().lock() else {
        return FfiStatusCode::Internal as u8;
    };

    runtime.clear_session_history();
    FfiStatusCode::Success as u8
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
    with_runtime_mut("syntic_dictation_start", |runtime| {
        runtime.dictation_session_mut().start_listening()
    }) as u8
}

/// Updates live transcription text while dictation is listening.
///
/// Returns a numeric FFI status code.
#[unsafe(no_mangle)]
pub extern "C" fn syntic_dictation_append_partial(text: *const c_char) -> u8 {
    let transcript = match parse_utf8_input(text) {
        Ok(value) => value,
        Err(error) => {
            if let Ok(mut runtime) = runtime_mutex().lock() {
                runtime.record_error_event(
                    "ffi.input",
                    "dictation_append_partial_invalid_input",
                    "append_partial received invalid UTF-8 or null input pointer",
                );
            }
            return error as u8;
        }
    };

    with_runtime_mut("syntic_dictation_append_partial", |runtime| {
        runtime.dictation_session_mut().append_partial(&transcript)
    }) as u8
}

/// Finalizes dictation and moves it to review state.
///
/// Returns a numeric FFI status code.
#[unsafe(no_mangle)]
pub extern "C" fn syntic_dictation_finalize_review(text: *const c_char) -> u8 {
    let transcript = match parse_utf8_input(text) {
        Ok(value) => value,
        Err(error) => {
            if let Ok(mut runtime) = runtime_mutex().lock() {
                runtime.record_error_event(
                    "ffi.input",
                    "dictation_finalize_review_invalid_input",
                    "finalize_review received invalid UTF-8 or null input pointer",
                );
            }
            return error as u8;
        }
    };

    with_runtime_mut("syntic_dictation_finalize_review", |runtime| {
        runtime.dictation_session_mut().finalize_review(&transcript)
    }) as u8
}

/// Confirms the reviewed dictation text.
///
/// Returns a numeric FFI status code.
#[unsafe(no_mangle)]
pub extern "C" fn syntic_dictation_confirm() -> u8 {
    let Ok(mut runtime) = runtime_mutex().lock() else {
        return FfiStatusCode::Internal as u8;
    };

    let snapshot = runtime.dictation_session().snapshot();
    let phase_before = snapshot.phase;
    let review_transcript_length = snapshot.review_transcript.chars().count();
    let review_transcript_length = u32::try_from(review_transcript_length).unwrap_or(u32::MAX);

    match runtime.dictation_session_mut().confirm() {
        Ok(()) => {
            if phase_before == DictationPhase::Reviewing {
                runtime.record_dictation_review_confirmed_domain_event(
                    "ffi.dictation",
                    phase_before.as_str(),
                    review_transcript_length,
                );
            }
            FfiStatusCode::Success as u8
        }
        Err(error) => {
            runtime.record_error_event(
                "ffi.dictation",
                error.as_str(),
                &format!(
                    "Dictation transition failed in `syntic_dictation_confirm`: {}",
                    error.as_str()
                ),
            );
            map_transition_error(error) as u8
        }
    }
}

/// Cancels the current dictation session.
///
/// Returns a numeric FFI status code.
#[unsafe(no_mangle)]
pub extern "C" fn syntic_dictation_cancel() -> u8 {
    let Ok(mut runtime) = runtime_mutex().lock() else {
        return FfiStatusCode::Internal as u8;
    };

    let snapshot = runtime.dictation_session().snapshot();
    let phase_before = snapshot.phase;
    let review_transcript_length = snapshot.review_transcript.chars().count();
    let review_transcript_length = u32::try_from(review_transcript_length).unwrap_or(u32::MAX);

    match runtime.dictation_session_mut().cancel() {
        Ok(()) => {
            if phase_before == DictationPhase::Reviewing {
                runtime.record_dictation_review_cancelled_domain_event(
                    "ffi.dictation",
                    phase_before.as_str(),
                    review_transcript_length,
                );
            }
            FfiStatusCode::Success as u8
        }
        Err(error) => {
            runtime.record_error_event(
                "ffi.dictation",
                error.as_str(),
                &format!(
                    "Dictation transition failed in `syntic_dictation_cancel`: {}",
                    error.as_str()
                ),
            );
            map_transition_error(error) as u8
        }
    }
}

/// Moves dictation state to `failed` and sets an error message.
///
/// Returns a numeric FFI status code.
#[unsafe(no_mangle)]
pub extern "C" fn syntic_dictation_fail(message: *const c_char) -> u8 {
    let failure_message = match parse_utf8_input(message) {
        Ok(value) => value,
        Err(error) => {
            if let Ok(mut runtime) = runtime_mutex().lock() {
                runtime.record_error_event(
                    "ffi.input",
                    "dictation_fail_invalid_input",
                    "dictation_fail received invalid UTF-8 or null input pointer",
                );
            }
            return error as u8;
        }
    };

    let Ok(mut runtime) = runtime_mutex().lock() else {
        return FfiStatusCode::Internal as u8;
    };

    runtime.dictation_session_mut().fail(&failure_message);
    runtime.record_error_event("ffi.dictation", "dictation_failed", &failure_message);
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
    use std::sync::{Mutex, MutexGuard, OnceLock};

    use super::{
        syntic_command_classify_json, syntic_command_safety_json, syntic_core_event_report_error,
        syntic_core_event_report_permission, syntic_core_event_report_telemetry,
        syntic_core_events_clear, syntic_core_events_since_json, syntic_core_version,
        syntic_dictation_append_partial, syntic_dictation_cancel, syntic_dictation_confirm,
        syntic_dictation_finalize_review, syntic_dictation_reset, syntic_dictation_start,
        syntic_dictation_state_json, syntic_domain_events_clear, syntic_domain_events_since_json,
        syntic_runtime_health_json, syntic_session_history_clear,
        syntic_session_history_mark_last_confirmed_undone, syntic_session_history_record,
        syntic_session_history_since_json, syntic_string_free, syntic_stt_route_json,
        syntic_tool_runtime_signals_since_json,
    };

    fn test_guard() -> MutexGuard<'static, ()> {
        static TEST_LOCK: OnceLock<Mutex<()>> = OnceLock::new();
        TEST_LOCK
            .get_or_init(|| Mutex::new(()))
            .lock()
            .expect("ffi test lock poisoned")
    }

    #[test]
    fn core_version_pointer_is_valid_utf8() {
        let _guard = test_guard();
        let version_pointer = syntic_core_version();
        assert!(!version_pointer.is_null());

        // SAFETY: `syntic_core_version` returns a static C string pointer.
        let version = unsafe { CStr::from_ptr(version_pointer) };
        assert!(!version.to_str().expect("utf8").is_empty());
    }

    #[test]
    fn health_json_can_be_freed() {
        let _guard = test_guard();
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
        let _guard = test_guard();
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
        let _guard = test_guard();
        assert_eq!(syntic_dictation_reset(), 0);
        assert_eq!(syntic_dictation_start(), 0);
        assert_eq!(syntic_dictation_start(), 10);
    }

    #[test]
    fn review_cancel_emits_domain_event_and_tool_runtime_signal() {
        let _guard = test_guard();
        assert_eq!(syntic_dictation_reset(), 0);
        assert_eq!(syntic_domain_events_clear(), 0);
        assert_eq!(syntic_dictation_start(), 0);

        let review = CString::new("hello review").expect("cstring");
        assert_eq!(syntic_dictation_finalize_review(review.as_ptr()), 0);
        assert_eq!(syntic_dictation_cancel(), 0);

        let domain_events_pointer = syntic_domain_events_since_json(0, 16);
        assert!(!domain_events_pointer.is_null());

        // SAFETY: pointer returned by `syntic_domain_events_since_json` is a valid C string.
        let domain_events_payload = unsafe { CStr::from_ptr(domain_events_pointer) };
        let domain_events_text = domain_events_payload.to_str().expect("utf8");
        assert!(domain_events_text.contains("\"name\":\"dictation_review_cancelled\""));
        assert!(domain_events_text.contains("\"phase_before\":\"reviewing\""));

        // SAFETY: `domain_events_pointer` came from `syntic_domain_events_since_json`.
        unsafe { syntic_string_free(domain_events_pointer) };

        let signals_pointer = syntic_tool_runtime_signals_since_json(0, 16);
        assert!(!signals_pointer.is_null());

        // SAFETY: pointer returned by `syntic_tool_runtime_signals_since_json` is a valid C string.
        let signals_payload = unsafe { CStr::from_ptr(signals_pointer) };
        let signals_text = signals_payload.to_str().expect("utf8");
        assert!(signals_text.contains("\"action\":\"abort_pending_tool_invocations\""));
        assert!(signals_text.contains("\"reason\":\"dictation_review_cancelled\""));

        // SAFETY: `signals_pointer` came from `syntic_tool_runtime_signals_since_json`.
        unsafe { syntic_string_free(signals_pointer) };
    }

    #[test]
    fn review_confirm_emits_domain_event_and_tool_runtime_signal() {
        let _guard = test_guard();
        assert_eq!(syntic_dictation_reset(), 0);
        assert_eq!(syntic_domain_events_clear(), 0);
        assert_eq!(syntic_dictation_start(), 0);

        let review = CString::new("hello confirm").expect("cstring");
        assert_eq!(syntic_dictation_finalize_review(review.as_ptr()), 0);
        assert_eq!(syntic_dictation_confirm(), 0);

        let domain_events_pointer = syntic_domain_events_since_json(0, 16);
        assert!(!domain_events_pointer.is_null());

        // SAFETY: pointer returned by `syntic_domain_events_since_json` is a valid C string.
        let domain_events_payload = unsafe { CStr::from_ptr(domain_events_pointer) };
        let domain_events_text = domain_events_payload.to_str().expect("utf8");
        assert!(domain_events_text.contains("\"name\":\"dictation_review_confirmed\""));
        assert!(domain_events_text.contains("\"phase_before\":\"reviewing\""));

        // SAFETY: `domain_events_pointer` came from `syntic_domain_events_since_json`.
        unsafe { syntic_string_free(domain_events_pointer) };

        let signals_pointer = syntic_tool_runtime_signals_since_json(0, 16);
        assert!(!signals_pointer.is_null());

        // SAFETY: pointer returned by `syntic_tool_runtime_signals_since_json` is a valid C string.
        let signals_payload = unsafe { CStr::from_ptr(signals_pointer) };
        let signals_text = signals_payload.to_str().expect("utf8");
        assert!(signals_text.contains("\"action\":\"commit_pending_tool_invocations\""));
        assert!(signals_text.contains("\"reason\":\"dictation_review_confirmed\""));

        // SAFETY: `signals_pointer` came from `syntic_tool_runtime_signals_since_json`.
        unsafe { syntic_string_free(signals_pointer) };
    }

    #[test]
    fn append_partial_with_null_pointer_returns_null_status() {
        let _guard = test_guard();
        assert_eq!(syntic_dictation_reset(), 0);
        assert_eq!(syntic_dictation_start(), 0);
        assert_eq!(syntic_dictation_append_partial(ptr::null()), 20);
    }

    #[test]
    fn command_classification_json_contains_timer_kind() {
        let _guard = test_guard();
        let utterance = CString::new("Stelle einen Timer auf 20min").expect("cstring");
        let payload_pointer = syntic_command_classify_json(utterance.as_ptr());
        assert!(!payload_pointer.is_null());

        // SAFETY: pointer returned by `syntic_command_classify_json` is a valid C string.
        let payload = unsafe { CStr::from_ptr(payload_pointer) };
        let payload_text = payload.to_str().expect("utf8");
        assert!(payload_text.contains("\"kind\":\"set_timer\""));
        assert!(payload_text.contains("\"timer_duration\":\"20min\""));

        // SAFETY: `payload_pointer` came from `syntic_command_classify_json`.
        unsafe { syntic_string_free(payload_pointer) };
    }

    #[test]
    fn command_safety_json_marks_rename_as_destructive() {
        let _guard = test_guard();
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

    #[test]
    fn command_classification_json_includes_move_destination_kind() {
        let _guard = test_guard();
        let utterance = CString::new("move file report to /tmp/archive").expect("cstring");
        let payload_pointer = syntic_command_classify_json(utterance.as_ptr());
        assert!(!payload_pointer.is_null());

        // SAFETY: pointer returned by `syntic_command_classify_json` is a valid C string.
        let payload = unsafe { CStr::from_ptr(payload_pointer) };
        let payload_text = payload.to_str().expect("utf8");
        assert!(payload_text.contains("\"move_destination\":\"/tmp/archive\""));
        assert!(payload_text.contains("\"move_destination_kind\":\"absolute_path\""));

        // SAFETY: `payload_pointer` came from `syntic_command_classify_json`.
        unsafe { syntic_string_free(payload_pointer) };
    }

    #[test]
    fn stt_route_auto_short_utterance_prefers_local() {
        let _guard = test_guard();
        let payload_pointer = syntic_stt_route_json(2, 0, 1, 2_000);
        assert!(!payload_pointer.is_null());

        // SAFETY: pointer returned by `syntic_stt_route_json` is a valid C string.
        let payload = unsafe { CStr::from_ptr(payload_pointer) };
        let payload_text = payload.to_str().expect("utf8");
        assert!(payload_text.contains("\"provider\":\"apple_speech_recognizer\""));

        // SAFETY: `payload_pointer` came from `syntic_stt_route_json`.
        unsafe { syntic_string_free(payload_pointer) };
    }

    #[test]
    fn core_error_event_is_exposed_via_events_json() {
        let _guard = test_guard();
        assert_eq!(syntic_core_events_clear(), 0);

        let source = CString::new("macos.pipeline").expect("cstring");
        let code = CString::new("audio_capture_start_failed").expect("cstring");
        let message = CString::new("engine start failed").expect("cstring");
        assert_eq!(
            syntic_core_event_report_error(source.as_ptr(), code.as_ptr(), message.as_ptr()),
            0
        );

        let payload_pointer = syntic_core_events_since_json(0, 20);
        assert!(!payload_pointer.is_null());

        // SAFETY: pointer returned by `syntic_core_events_since_json` is a valid C string.
        let payload = unsafe { CStr::from_ptr(payload_pointer) };
        let payload_text = payload.to_str().expect("utf8");
        assert!(payload_text.contains("\"kind\":\"error\""));
        assert!(payload_text.contains("\"code\":\"audio_capture_start_failed\""));

        // SAFETY: `payload_pointer` came from `syntic_core_events_since_json`.
        unsafe { syntic_string_free(payload_pointer) };
    }

    #[test]
    fn core_permission_event_accepts_null_detail_pointer() {
        let _guard = test_guard();
        assert_eq!(syntic_core_events_clear(), 0);

        let source = CString::new("macos.audio").expect("cstring");
        let permission = CString::new("microphone").expect("cstring");
        let status = CString::new("denied").expect("cstring");
        assert_eq!(
            syntic_core_event_report_permission(
                source.as_ptr(),
                permission.as_ptr(),
                status.as_ptr(),
                ptr::null()
            ),
            0
        );

        let payload_pointer = syntic_core_events_since_json(0, 20);
        assert!(!payload_pointer.is_null());

        // SAFETY: pointer returned by `syntic_core_events_since_json` is a valid C string.
        let payload = unsafe { CStr::from_ptr(payload_pointer) };
        let payload_text = payload.to_str().expect("utf8");
        assert!(payload_text.contains("\"kind\":\"permission\""));
        assert!(payload_text.contains("\"permission\":\"microphone\""));
        assert!(payload_text.contains("\"status\":\"denied\""));

        // SAFETY: `payload_pointer` came from `syntic_core_events_since_json`.
        unsafe { syntic_string_free(payload_pointer) };
    }

    #[test]
    fn core_telemetry_event_is_exposed_via_events_json() {
        let _guard = test_guard();
        assert_eq!(syntic_core_events_clear(), 0);

        let source = CString::new("macos.pipeline").expect("cstring");
        let category = CString::new("e2e").expect("cstring");
        let action = CString::new("phase_changed").expect("cstring");
        let status = CString::new("ok").expect("cstring");
        let context_json = CString::new("{\"phase\":\"listening\"}").expect("cstring");
        assert_eq!(
            syntic_core_event_report_telemetry(
                source.as_ptr(),
                category.as_ptr(),
                action.as_ptr(),
                status.as_ptr(),
                context_json.as_ptr(),
                80
            ),
            0
        );

        let payload_pointer = syntic_core_events_since_json(0, 20);
        assert!(!payload_pointer.is_null());

        // SAFETY: pointer returned by `syntic_core_events_since_json` is a valid C string.
        let payload = unsafe { CStr::from_ptr(payload_pointer) };
        let payload_text = payload.to_str().expect("utf8");
        assert!(payload_text.contains("\"kind\":\"telemetry\""));
        assert!(payload_text.contains("\"category\":\"e2e\""));
        assert!(payload_text.contains("\"action\":\"phase_changed\""));
        assert!(payload_text.contains("\"value_ms\":80"));

        // SAFETY: `payload_pointer` came from `syntic_core_events_since_json`.
        unsafe { syntic_string_free(payload_pointer) };
    }

    #[test]
    fn session_history_record_is_exposed_via_feed_json() {
        let _guard = test_guard();
        assert_eq!(syntic_session_history_clear(), 0);

        let outcome = CString::new("confirmed").expect("cstring");
        let transcript = CString::new("hello history").expect("cstring");
        let locale = CString::new("de-DE").expect("cstring");
        let provider = CString::new("apple_speech_recognizer").expect("cstring");
        let injection = CString::new("injected").expect("cstring");
        assert_eq!(
            syntic_session_history_record(
                outcome.as_ptr(),
                transcript.as_ptr(),
                locale.as_ptr(),
                provider.as_ptr(),
                940,
                ptr::null(),
                injection.as_ptr()
            ),
            0
        );

        let payload_pointer = syntic_session_history_since_json(0, 20);
        assert!(!payload_pointer.is_null());

        // SAFETY: pointer returned by `syntic_session_history_since_json` is a valid C string.
        let payload = unsafe { CStr::from_ptr(payload_pointer) };
        let payload_text = payload.to_str().expect("utf8");
        assert!(payload_text.contains("\"outcome\":\"confirmed\""));
        assert!(payload_text.contains("\"transcript\":\"hello history\""));
        assert!(payload_text.contains("\"injection_disposition\":\"injected\""));
        assert!(payload_text.contains("\"duration_ms\":940"));

        // SAFETY: `payload_pointer` came from `syntic_session_history_since_json`.
        unsafe { syntic_string_free(payload_pointer) };
    }

    #[test]
    fn session_history_mark_undone_updates_latest_confirmed_record() {
        let _guard = test_guard();
        assert_eq!(syntic_session_history_clear(), 0);

        let outcome = CString::new("confirmed").expect("cstring");
        let transcript = CString::new("undo me").expect("cstring");
        let locale = CString::new("de-DE").expect("cstring");
        let provider = CString::new("apple_speech_recognizer").expect("cstring");
        assert_eq!(
            syntic_session_history_record(
                outcome.as_ptr(),
                transcript.as_ptr(),
                locale.as_ptr(),
                provider.as_ptr(),
                0,
                ptr::null(),
                ptr::null()
            ),
            0
        );

        assert_eq!(syntic_session_history_mark_last_confirmed_undone(), 0);

        let payload_pointer = syntic_session_history_since_json(0, 20);
        assert!(!payload_pointer.is_null());

        // SAFETY: pointer returned by `syntic_session_history_since_json` is a valid C string.
        let payload = unsafe { CStr::from_ptr(payload_pointer) };
        let payload_text = payload.to_str().expect("utf8");
        assert!(payload_text.contains("\"undone_at_ms\":"));
        assert!(!payload_text.contains("\"undone_at_ms\":null"));

        // SAFETY: `payload_pointer` came from `syntic_session_history_since_json`.
        unsafe { syntic_string_free(payload_pointer) };
    }

    #[test]
    fn session_history_record_rejects_unknown_outcome() {
        let _guard = test_guard();
        assert_eq!(syntic_session_history_clear(), 0);

        let outcome = CString::new("unexpected").expect("cstring");
        let transcript = CString::new("bad").expect("cstring");
        let locale = CString::new("de-DE").expect("cstring");
        let provider = CString::new("apple_speech_recognizer").expect("cstring");
        assert_eq!(
            syntic_session_history_record(
                outcome.as_ptr(),
                transcript.as_ptr(),
                locale.as_ptr(),
                provider.as_ptr(),
                0,
                ptr::null(),
                ptr::null()
            ),
            22
        );
    }
}
