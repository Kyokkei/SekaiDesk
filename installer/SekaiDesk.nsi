; SekaiDesk NSIS Installer Script
Unicode True

!define APP_NAME "SekaiDesk"
!define APP_VERSION "0.1.0"
!define APP_PUBLISHER "Yozora · SekaiDesk"
!define APP_EXE "SekaiDesk.exe"
!define UNINST_REG_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\SekaiDesk"

Name "${APP_NAME} ${APP_VERSION}"
OutFile "SekaiDesk-Setup.exe"
InstallDir "$LOCALAPPDATA\Programs\SekaiDesk"
InstallDirRegKey HKCU "${UNINST_REG_KEY}" "InstallLocation"
RequestExecutionLevel user
SetCompressor /SOLID lzma
ShowInstDetails show
ShowUninstDetails show

!include "MUI2.nsh"
!include "FileFunc.nsh"

!define MUI_ICON "SekaiDesk.ico"
!define MUI_UNICON "SekaiDesk.ico"
!define MUI_ABORTWARNING

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES

!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP_EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Launch ${APP_NAME} now"
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

Section "SekaiDesk" SecMain
    SectionIn RO

    ; Stop running SekaiDesk before overwriting binaries
    nsExec::ExecToStack 'taskkill /F /IM ${APP_EXE}'
    Pop $0
    Pop $1
    Sleep 600

    SetOutPath "$INSTDIR"
    File /r "stage/*"

    WriteUninstaller "$INSTDIR\Uninstall.exe"

    ; Start Menu & Desktop shortcuts
    CreateDirectory "$SMPROGRAMS\${APP_NAME}"
    CreateShortCut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0
    CreateShortCut "$SMPROGRAMS\${APP_NAME}\Uninstall ${APP_NAME}.lnk" "$INSTDIR\Uninstall.exe" "" "$INSTDIR\Uninstall.exe" 0
    CreateShortCut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0

    ; Windows Add/Remove Programs metadata (per-user HKCU)
    WriteRegStr HKCU "${UNINST_REG_KEY}" "DisplayName" "${APP_NAME}"
    WriteRegStr HKCU "${UNINST_REG_KEY}" "DisplayVersion" "${APP_VERSION}"
    WriteRegStr HKCU "${UNINST_REG_KEY}" "Publisher" "${APP_PUBLISHER}"
    WriteRegStr HKCU "${UNINST_REG_KEY}" "DisplayIcon" "$INSTDIR\${APP_EXE},0"
    WriteRegStr HKCU "${UNINST_REG_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
    WriteRegStr HKCU "${UNINST_REG_KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
    WriteRegStr HKCU "${UNINST_REG_KEY}" "InstallLocation" "$INSTDIR"
    WriteRegDWORD HKCU "${UNINST_REG_KEY}" "NoModify" 1
    WriteRegDWORD HKCU "${UNINST_REG_KEY}" "NoRepair" 1

    ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
    IntFmt $0 "0x%08X" $0
    WriteRegDWORD HKCU "${UNINST_REG_KEY}" "EstimatedSize" "$0"
SectionEnd

Section "Uninstall"
    nsExec::ExecToStack 'taskkill /F /IM ${APP_EXE}'
    Pop $0
    Pop $1
    Sleep 600

    Delete "$DESKTOP\${APP_NAME}.lnk"
    Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"
    Delete "$SMPROGRAMS\${APP_NAME}\Uninstall ${APP_NAME}.lnk"
    RMDir "$SMPROGRAMS\${APP_NAME}"

    RMDir /r "$INSTDIR"
    DeleteRegKey HKCU "${UNINST_REG_KEY}"
SectionEnd
