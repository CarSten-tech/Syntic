//! C ABI bridge for embedding `syntic-core` into platform-specific shells.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::OnceLock;

use syntic_core::{CORE_VERSION, CoreRuntime};

static CORE_VERSION_CSTRING: OnceLock<CString> = OnceLock::new();

fn core_version_cstr() -> &'static CStr {
    CORE_VERSION_CSTRING
        .get_or_init(|| CString::new(CORE_VERSION).expect("CORE_VERSION must not contain NUL"))
        .as_c_str()
}

/// Returns a pointer to a static NUL-terminated UTF-8 string.
///
/// The returned pointer must not be freed by the caller.
#[unsafe(no_mangle)]
pub extern "C" fn syntic_core_version() -> *const c_char {
    core_version_cstr().as_ptr()
}

/// Returns a heap-allocated JSON string with runtime health metadata.
///
/// The caller owns the returned pointer and must release it using
/// `syntic_string_free`.
///
/// # Panics
///
/// Panics only if the generated JSON contains an interior NUL byte, which is
/// not expected for the fixed runtime fields used here.
#[unsafe(no_mangle)]
pub extern "C" fn syntic_runtime_health_json() -> *mut c_char {
    let runtime = CoreRuntime::new();
    let snapshot = runtime.health_snapshot();
    let payload = format!(
        "{{\"service_name\":\"{}\",\"version\":\"{}\",\"status\":\"{}\"}}",
        snapshot.service_name, snapshot.version, snapshot.status
    );

    CString::new(payload)
        .expect("runtime health payload must not contain NUL")
        .into_raw()
}

/// Frees strings created by `syntic_runtime_health_json`.
///
/// # Safety
///
/// `ptr` must have been allocated by `CString::into_raw` in this library.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn syntic_string_free(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }

    // SAFETY: Caller contract guarantees provenance from `CString::into_raw`.
    unsafe {
        drop(CString::from_raw(ptr));
    }
}

#[cfg(test)]
mod tests {
    use std::ffi::CStr;

    use super::{syntic_core_version, syntic_runtime_health_json, syntic_string_free};

    #[test]
    fn core_version_pointer_is_valid_utf8() {
        let version_ptr = syntic_core_version();
        assert!(!version_ptr.is_null());

        // SAFETY: pointer returned by `syntic_core_version` points to static C string.
        let version = unsafe { CStr::from_ptr(version_ptr) };
        assert!(!version.to_str().expect("utf8").is_empty());
    }

    #[test]
    fn health_json_can_be_freed() {
        let payload_ptr = syntic_runtime_health_json();
        assert!(!payload_ptr.is_null());

        // SAFETY: pointer returned by `syntic_runtime_health_json` is valid C string.
        let payload = unsafe { CStr::from_ptr(payload_ptr) };
        let payload_text = payload.to_str().expect("utf8");
        assert!(payload_text.contains("\"service_name\":\"syntic-core\""));

        // SAFETY: `payload_ptr` came from `syntic_runtime_health_json`.
        unsafe { syntic_string_free(payload_ptr) };
    }
}
