import Foundation

enum FinderContextStatus: String {
    case ok
    case emptySelection
    case finderNotRunning
    case scriptError
}

struct FinderContextSnapshot {
    let status: FinderContextStatus
    let finderRunning: Bool
    let finderFrontmost: Bool
    let windowCount: Int
    let viewName: String
    let selectedPaths: [String]
    let errorCode: Int?
    let errorMessage: String?
}

protocol FinderContextProviding {
    func currentSelectionSnapshot() -> FinderContextSnapshot
}

struct MacOSFinderContextAdapter: FinderContextProviding {
    func currentSelectionSnapshot() -> FinderContextSnapshot {
        let scriptSource = """
        set finderRunning to false
        set finderFrontmost to false
        set finderWindowCount to 0
        set finderView to \"none\"
        set selectedCount to 0
        set selectedPaths to \"\"

        try
          tell application \"System Events\"
            set finderRunning to (exists process \"Finder\")
            if finderRunning then
              set finderFrontmost to frontmost of process \"Finder\"
            end if
          end tell

          if finderRunning then
            tell application \"Finder\"
              set finderWindowCount to count of windows
              if finderWindowCount > 0 then
                set finderView to (current view of front window) as string
              end if
              set selectedCount to count of selection
              if selectedCount > 0 then
                set pathList to {}
                repeat with selectedItem in selection
                  set end of pathList to POSIX path of (selectedItem as alias)
                end repeat
                set AppleScript's text item delimiters to linefeed
                set selectedPaths to pathList as string
                set AppleScript's text item delimiters to \"\"
              end if
            end tell
          end if
        on error errMsg number errNum
          return \"error\" & tab & (errNum as string) & tab & errMsg & tab & \"false\" & tab & \"false\" & tab & \"0\" & tab & \"none\" & tab & \"0\" & tab & \"\"
        end try

        return \"ok\" & tab & \"0\" & tab & \"-\" & tab & (finderRunning as string) & tab & (finderFrontmost as string) & tab & (finderWindowCount as string) & tab & finderView & tab & (selectedCount as string) & tab & selectedPaths
        """

        var scriptError: NSDictionary?
        guard let script = NSAppleScript(source: scriptSource) else {
            return FinderContextSnapshot(
                status: .scriptError,
                finderRunning: false,
                finderFrontmost: false,
                windowCount: 0,
                viewName: "none",
                selectedPaths: [],
                errorCode: nil,
                errorMessage: "NSAppleScript konnte nicht erstellt werden."
            )
        }

        let resultDescriptor = script.executeAndReturnError(&scriptError)
        if let scriptError {
            return FinderContextSnapshot(
                status: .scriptError,
                finderRunning: false,
                finderFrontmost: false,
                windowCount: 0,
                viewName: "none",
                selectedPaths: [],
                errorCode: scriptError[NSAppleScript.errorNumber] as? Int,
                errorMessage: scriptError[NSAppleScript.errorMessage] as? String
            )
        }

        let rawOutput = resultDescriptor.stringValue ?? ""
        let fields = rawOutput.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)

        guard fields.count >= 9 else {
            return FinderContextSnapshot(
                status: .scriptError,
                finderRunning: false,
                finderFrontmost: false,
                windowCount: 0,
                viewName: "none",
                selectedPaths: [],
                errorCode: nil,
                errorMessage: "Unerwartete Script-Ausgabe: \(rawOutput)"
            )
        }

        let result = fields[0]
        let errorCode = Int(fields[1])
        let errorMessage = fields[2] == "-" ? nil : fields[2]
        let finderRunning = fields[3] == "true"
        let finderFrontmost = fields[4] == "true"
        let windowCount = Int(fields[5]) ?? 0
        let viewName = fields[6]
        let selectedCount = Int(fields[7]) ?? 0
        let selectedPaths = fields[8]
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map(String.init)
            .filter { !$0.isEmpty }

        if result != "ok" {
            return FinderContextSnapshot(
                status: .scriptError,
                finderRunning: finderRunning,
                finderFrontmost: finderFrontmost,
                windowCount: windowCount,
                viewName: viewName,
                selectedPaths: selectedPaths,
                errorCode: errorCode,
                errorMessage: errorMessage ?? "Unbekannter Script-Fehler"
            )
        }

        if !finderRunning {
            return FinderContextSnapshot(
                status: .finderNotRunning,
                finderRunning: false,
                finderFrontmost: finderFrontmost,
                windowCount: windowCount,
                viewName: viewName,
                selectedPaths: [],
                errorCode: nil,
                errorMessage: nil
            )
        }

        if selectedCount == 0 {
            return FinderContextSnapshot(
                status: .emptySelection,
                finderRunning: true,
                finderFrontmost: finderFrontmost,
                windowCount: windowCount,
                viewName: viewName,
                selectedPaths: [],
                errorCode: nil,
                errorMessage: nil
            )
        }

        return FinderContextSnapshot(
            status: .ok,
            finderRunning: true,
            finderFrontmost: finderFrontmost,
            windowCount: windowCount,
            viewName: viewName,
            selectedPaths: selectedPaths,
            errorCode: nil,
            errorMessage: nil
        )
    }
}
