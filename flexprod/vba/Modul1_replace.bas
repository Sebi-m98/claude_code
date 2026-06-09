Attribute VB_Name = "Modul1"
Option Explicit

' v2.7 Zurue-Ltg-Logik vereinfacht: 1-Klick-Toggle Ein/Ausblenden.
' Das alte frmZurueLtg-Dialog mit "Loeschen" entfaellt - Daten werden
' nicht mehr geloescht, nur ausgeblendet (reversibel).

Public Sub ZurueLtg_Klicken()
    Dim ws As Worksheet
    Set ws = ActiveWorkbook.Sheets("Schaltzettel")

    Dim intMaxCol As Integer
    intMaxCol = func_MaxColumn(2) + 3
    Dim intColLSZ As Integer
    intColLSZ = Modul_Umschaltung.FindColByHeader("LSZ", intMaxCol)
    If intColLSZ = 0 Then
        MsgBox "Spalte 'LSZ' nicht gefunden - keine Zurue-Erkennung moeglich.", vbExclamation
        Exit Sub
    End If

    Dim lngMaxRow As Long
    lngMaxRow = ws.UsedRange.Rows.Count

    ' Status pruefen: sind die Zurue-Zeilen aktuell ausgeblendet?
    Dim hidden As Boolean, count As Long, hidCount As Long
    hidden = False
    count = 0
    hidCount = 0
    Dim r As Long
    For r = 3 To lngMaxRow
        If InStr(1, LCase(ws.Cells(r, intColLSZ).Value), "zurue") > 0 Then
            count = count + 1
            If ws.Rows(r).Hidden Then hidCount = hidCount + 1
        End If
    Next r

    If count = 0 Then
        MsgBox "Keine Zurue-Leitungen im Schaltzettel gefunden.", vbInformation
        Exit Sub
    End If

    ' Mehrheits-Heuristik: wenn mehr als die Haelfte sichtbar => ausblenden, sonst einblenden
    Dim doHide As Boolean
    doHide = (hidCount * 2 < count)

    Application.ScreenUpdating = False
    For r = 3 To lngMaxRow
        If InStr(1, LCase(ws.Cells(r, intColLSZ).Value), "zurue") > 0 Then
            ws.Rows(r).Hidden = doHide
        End If
    Next r
    Application.ScreenUpdating = True

    If doHide Then
        MsgBox count & " Zurue-Leitungen ausgeblendet.", vbInformation
    Else
        MsgBox count & " Zurue-Leitungen wieder eingeblendet.", vbInformation
    End If
End Sub

' Vollstaendiges Loeschen (alte Funktion, optional fuer Skripte)
Public Sub ZurueLoeschen_Klicken()
    Dim ans As VbMsgBoxResult
    ans = MsgBox("Achtung: Zurue-Leitungen werden aus dem Schaltzettel GELOESCHT (irreversibel ausser via 'Letzte Umschaltung rueckgaengig'-Snapshot pro Spalte). Fortfahren?", _
                 vbYesNo + vbExclamation, "Zurue-Ltg loeschen")
    If ans <> vbYes Then Exit Sub

    Dim ws As Worksheet
    Set ws = ActiveWorkbook.Sheets("Schaltzettel")
    Dim intMaxCol As Integer
    intMaxCol = func_MaxColumn(2) + 3
    Dim intColLSZ As Integer
    intColLSZ = Modul_Umschaltung.FindColByHeader("LSZ", intMaxCol)
    If intColLSZ = 0 Then Exit Sub

    Application.ScreenUpdating = False
    Dim r As Long, deletedCount As Long
    For r = ws.UsedRange.Rows.Count To 3 Step -1
        If InStr(1, LCase(ws.Cells(r, intColLSZ).Value), "zurue") > 0 Then
            ws.Rows(r).Delete
            deletedCount = deletedCount + 1
        End If
    Next r
    Application.ScreenUpdating = True
    MsgBox deletedCount & " Zurue-Zeilen geloescht.", vbInformation
End Sub
