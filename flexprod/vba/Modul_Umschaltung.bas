Attribute VB_Name = "Modul_Umschaltung"
Option Explicit

' v2.7 Neue Umschaltung-Logik mit Anzahl-Stifte-Begrenzung und Undo-Snapshot
' Eingaben werden via frmUmschaltung erfasst (das Form ergaenzt zur Laufzeit
' das Feld txtAnzahlStifte ueber Controls.Add im UserForm_Initialize).
' Wird txtAnzahlStifte leer gelassen oder 0 eingetragen, gilt unbegrenzt.

Public Const UNDO_SHEET As String = "_UndoBuffer"

' Ergebnis pro Umschaltung
Public Type UmschResult
    Anzahl As Long
    Abgebrochen As Boolean
End Type

' Spaltenindex einer Header-Zelle in Zeile 2 ermitteln (case-insensitive Substring)
Public Function FindColByHeader(ByVal needle As String, ByVal intMaxCol As Integer) As Integer
    Dim i As Integer
    Dim ws As Worksheet
    Set ws = ActiveWorkbook.Sheets("Schaltzettel")
    For i = 1 To intMaxCol
        If InStr(1, LCase(ws.Cells(2, i).Value), LCase(needle)) > 0 Then
            FindColByHeader = i
            Exit Function
        End If
    Next i
    FindColByHeader = 0
End Function

' Verbundene Zellen in Spalten D:E aufloesen (gleicher Wert in alle Zellen kopieren)
Public Sub UnmergeBlocks()
    Dim mrgCelle As Range
    For Each mrgCelle In Intersect(ActiveSheet.Columns("D:E"), ActiveSheet.UsedRange)
        If mrgCelle.MergeCells Then
            With mrgCelle.MergeArea
                .UnMerge
                .Value = mrgCelle.Value
            End With
        End If
    Next mrgCelle
End Sub

' Verbundzellen wiederherstellen (gleiche aufeinanderfolgende Leitungsbez. mergen)
Public Sub MergeAfterUmschaltung()
    Dim ws As Worksheet
    Set ws = ActiveSheet
    Dim lastRow As Long, r As Long, blockStart As Long, c As Integer
    lastRow = ws.Cells(ws.Rows.Count, "D").End(xlUp).Row
    Application.DisplayAlerts = False
    For c = 4 To 5
        blockStart = 3
        For r = 4 To lastRow + 1
            If r > lastRow Or ws.Cells(r, c).Value <> ws.Cells(blockStart, c).Value Then
                If r - 1 > blockStart Then
                    ws.Range(ws.Cells(blockStart, c), ws.Cells(r - 1, c)).Merge
                End If
                If r <= lastRow Then blockStart = r
            End If
        Next r
    Next c
    Application.DisplayAlerts = True
End Sub

' Snapshot fuer Undo: Spaltenwerte + Character-Formate sichern
Public Sub SnapshotColumnForUndo(ByVal intCol As Integer, ByVal lngMaxRow As Long, ByVal funcLabel As String)
    Dim wbk As Workbook
    Dim wsBuf As Worksheet
    Dim r As Long
    Set wbk = ActiveWorkbook

    On Error Resume Next
    Set wsBuf = wbk.Sheets(UNDO_SHEET)
    On Error GoTo 0
    If wsBuf Is Nothing Then
        Set wsBuf = wbk.Sheets.Add(After:=wbk.Sheets(wbk.Sheets.Count))
        wsBuf.Name = UNDO_SHEET
        wsBuf.Visible = xlSheetVeryHidden
    Else
        wsBuf.Cells.Clear
    End If

    wsBuf.Cells(1, 1).Value = "FlexProdUndo_v1"
    wsBuf.Cells(1, 2).Value = funcLabel
    wsBuf.Cells(1, 3).Value = intCol
    wsBuf.Cells(1, 4).Value = lngMaxRow
    wsBuf.Cells(1, 5).Value = Now

    Dim srcWs As Worksheet
    Set srcWs = wbk.Sheets("Schaltzettel")
    For r = 2 To lngMaxRow
        wsBuf.Cells(r, 1).Value = srcWs.Cells(r, intCol).Value
        SaveCharacterFormats srcWs.Cells(r, intCol), wsBuf.Cells(r, 2)
    Next r
End Sub

' Hilfsfunktion: speichert Character-Run-Formate als komprimierten String
Private Sub SaveCharacterFormats(ByVal src As Range, ByVal dst As Range)
    Dim s As String
    Dim L As Long, i As Long
    Dim ch As Object
    L = Len(src.Value)
    s = ""
    For i = 1 To L
        Set ch = src.Characters(Start:=i, Length:=1)
        s = s & EncodeFmt(ch.Font) & "|"
    Next i
    dst.Value = s
End Sub

Private Function EncodeFmt(ByVal fnt As Object) As String
    Dim st As String, color As String
    st = "0"
    If fnt.Strikethrough Then st = "1"
    On Error Resume Next
    color = CStr(fnt.Color)
    If color = "" Then color = "0"
    On Error GoTo 0
    EncodeFmt = st & ":" & color
End Function

' Restore: aus Snapshot zurueckschreiben
Public Sub Umschaltung_Undo()
    Dim wbk As Workbook
    Dim wsBuf As Worksheet, srcWs As Worksheet
    Set wbk = ActiveWorkbook

    On Error Resume Next
    Set wsBuf = wbk.Sheets(UNDO_SHEET)
    On Error GoTo 0
    If wsBuf Is Nothing Then
        MsgBox "Keine Umschaltung zum Rueckgaengigmachen vorhanden.", vbInformation
        Exit Sub
    End If

    If wsBuf.Cells(1, 1).Value <> "FlexProdUndo_v1" Then
        MsgBox "Undo-Buffer beschaedigt oder leer.", vbExclamation
        Exit Sub
    End If

    Dim funcLabel As String, intCol As Integer, lngMaxRow As Long
    funcLabel = wsBuf.Cells(1, 2).Value
    intCol = wsBuf.Cells(1, 3).Value
    lngMaxRow = wsBuf.Cells(1, 4).Value

    Dim ans As VbMsgBoxResult
    ans = MsgBox("Letzte Umschaltung (" & funcLabel & ") rueckgaengig machen?", vbYesNo + vbQuestion, "Undo")
    If ans <> vbYes Then Exit Sub

    Set srcWs = wbk.Sheets("Schaltzettel")
    Application.ScreenUpdating = False
    Application.DisplayAlerts = False

    Modul_Umschaltung.UnmergeBlocks

    Dim r As Long, val As String, fmtStr As String
    For r = 2 To lngMaxRow
        val = wsBuf.Cells(r, 1).Value
        fmtStr = wsBuf.Cells(r, 2).Value
        srcWs.Cells(r, intCol).Value = val
        RestoreCharacterFormats srcWs.Cells(r, intCol), fmtStr
    Next r

    srcWs.Columns(intCol).EntireColumn.AutoFit
    Modul_Umschaltung.MergeAfterUmschaltung

    wsBuf.Cells.Clear
    Application.DisplayAlerts = True
    Application.ScreenUpdating = True

    MsgBox "Umschaltung zurueckgesetzt.", vbInformation
End Sub

Private Sub RestoreCharacterFormats(ByVal cell As Range, ByVal fmtStr As String)
    Dim parts() As String, i As Long, fp() As String
    If Len(fmtStr) = 0 Then Exit Sub
    parts = Split(fmtStr, "|")
    For i = 0 To UBound(parts) - 1
        If Len(parts(i)) > 0 And i + 1 <= Len(cell.Value) Then
            fp = Split(parts(i), ":")
            With cell.Characters(Start:=i + 1, Length:=1).Font
                .Strikethrough = (fp(0) = "1")
                If UBound(fp) >= 1 And IsNumeric(fp(1)) Then .Color = CLng(fp(1))
            End With
        End If
    Next i
End Sub

' Kernroutine: Umschaltung mit Anzahl-Stifte-Begrenzung
' headerKey: "Stift an" oder "Stift ab" - sucht die Zielspalte
' evsAlt/evsNeu: alte/neue EVS-Bezeichnung
' stiftBegStr: Beginnwert (numerisch als String) oder "" fuer keine Stiftnummer
' anzahlMax: 0 = unbegrenzt, sonst max. Anzahl umzuschaltender Zeilen
' kvzFilter: optional, wenn nicht "" wird zusaetzlich auf KVz-Spalte gefiltert
Public Function UmschaltenStiftSpalte( _
    ByVal headerKey As String, _
    ByVal evsAlt As String, _
    ByVal evsNeu As String, _
    ByVal stiftBegStr As String, _
    ByVal anzahlMax As Long, _
    ByVal kvzFilter As String) As UmschResult

    Dim res As UmschResult
    res.Anzahl = 0
    res.Abgebrochen = False

    Dim ws As Worksheet
    Set ws = ActiveWorkbook.Sheets("Schaltzettel")

    Dim intMaxCol As Integer
    intMaxCol = func_MaxColumn(2) + 3

    Dim intColTarget As Integer, intColLSZ As Integer, intColKVz As Integer
    intColTarget = FindColByHeader(headerKey, intMaxCol)
    intColLSZ = FindColByHeader("LSZ", intMaxCol)
    If intColTarget = 0 Then
        MsgBox "Spalte '" & headerKey & "' nicht gefunden.", vbExclamation
        res.Abgebrochen = True
        UmschaltenStiftSpalte = res
        Exit Function
    End If
    If kvzFilter <> "" Then
        intColKVz = FindColByHeader("KVz", intMaxCol)
    End If

    Dim lngMaxRow As Long
    lngMaxRow = ws.UsedRange.Rows.Count

    SnapshotColumnForUndo intColTarget, lngMaxRow, "Umschaltung " & headerKey & " " & evsAlt & "->" & evsNeu

    Application.DisplayAlerts = False
    Application.ScreenUpdating = False

    UnmergeBlocks

    Dim intStiftNeu As Long
    If stiftBegStr <> "" And IsNumeric(stiftBegStr) Then
        intStiftNeu = CLng(stiftBegStr)
    Else
        intStiftNeu = 0
    End If

    Dim r As Long
    Dim sCell As String, arr() As String, sEvs As String, sStift As String
    Dim lAlt As Long, lNeu As Long, lStAlt As Long, lStNeu As Long

    For r = 3 To lngMaxRow
        ' Zurue Ltg. ueberspringen
        If intColLSZ > 0 Then
            If InStr(1, LCase(ws.Cells(r, intColLSZ).Value), "zurue") > 0 Then GoTo NextRow
        End If

        sCell = ws.Cells(r, intColTarget).Value
        If InStr(sCell, "/") = 0 Then GoTo NextRow

        arr = Split(sCell, "/")
        If UBound(arr) < 1 Then GoTo NextRow
        sEvs = arr(LBound(arr))
        sStift = arr(UBound(arr))
        If sEvs <> evsAlt Then GoTo NextRow

        ' KVz-Filter pruefen
        If kvzFilter <> "" And intColKVz > 0 Then
            If InStr(1, ws.Cells(r, intColKVz).Value, kvzFilter) = 0 Then GoTo NextRow
        End If

        lAlt = Len(sEvs)
        lNeu = Len(evsNeu)
        lStAlt = Len(sStift)
        lStNeu = Len(CStr(intStiftNeu))

        If intStiftNeu > 0 Then
            ws.Cells(r, intColTarget).Value = sEvs & evsNeu & "/" & sStift & CStr(intStiftNeu)
        Else
            ws.Cells(r, intColTarget).Value = sEvs & evsNeu & "/" & sStift
        End If

        ' Alte EVS durchgestrichen
        With ws.Cells(r, intColTarget).Characters(Start:=1, Length:=lAlt).Font
            .Strikethrough = True
        End With
        ' Neue EVS in Rot
        With ws.Cells(r, intColTarget).Characters(Start:=lAlt + 1, Length:=lNeu).Font
            .Strikethrough = False
            .Color = vbRed
        End With

        If intStiftNeu > 0 Then
            ' Alter Stift durchgestrichen
            With ws.Cells(r, intColTarget).Characters(Start:=lAlt + lNeu + 2, Length:=lStAlt).Font
                .Strikethrough = True
            End With
            ' Neuer Stift rot
            With ws.Cells(r, intColTarget).Characters(Start:=lAlt + lNeu + 2 + lStAlt, Length:=lStNeu).Font
                .Strikethrough = False
                .Color = vbRed
            End With
            intStiftNeu = intStiftNeu + 1
        End If

        res.Anzahl = res.Anzahl + 1
        DoEvents

        ' Anzahl-Stifte-Begrenzung
        If anzahlMax > 0 And res.Anzahl >= anzahlMax Then Exit For
NextRow:
    Next r

    ws.Columns(intColTarget).EntireColumn.AutoFit
    MergeAfterUmschaltung

    Application.DisplayAlerts = True
    Application.ScreenUpdating = True

    UmschaltenStiftSpalte = res
End Function

' Spezialfall HVT-L: anders strukturiert (Reihe/Leiste/Stift), eigene Logik
' Hier: vereinfachte Variante - Anzahl-Stifte-Limit ebenfalls einbinden
Public Function UmschaltenHvtL( _
    ByVal reiheAlt As String, ByVal reiheNeu As String, _
    ByVal leisteAlt As String, ByVal leisteNeu As String, _
    ByVal stiftBegStr As String, ByVal anzahlMax As Long) As UmschResult

    Dim res As UmschResult
    res.Anzahl = 0
    res.Abgebrochen = False

    Dim ws As Worksheet
    Set ws = ActiveWorkbook.Sheets("Schaltzettel")

    Dim intMaxCol As Integer
    intMaxCol = func_MaxColumn(2) + 3

    Dim intColHvt As Integer, intColLSZ As Integer
    intColHvt = FindColByHeader("HVt-L", intMaxCol)
    If intColHvt = 0 Then intColHvt = FindColByHeader("HVT", intMaxCol)
    intColLSZ = FindColByHeader("LSZ", intMaxCol)
    If intColHvt = 0 Then
        MsgBox "Spalte 'HVt-L' nicht gefunden.", vbExclamation
        res.Abgebrochen = True
        UmschaltenHvtL = res
        Exit Function
    End If

    Dim lngMaxRow As Long
    lngMaxRow = ws.UsedRange.Rows.Count

    SnapshotColumnForUndo intColHvt, lngMaxRow, "HVt-L Umschaltung " & reiheAlt & "/" & leisteAlt & "->" & reiheNeu & "/" & leisteNeu

    Application.DisplayAlerts = False
    Application.ScreenUpdating = False
    UnmergeBlocks

    Dim intStiftNeu As Long
    If stiftBegStr <> "" And IsNumeric(stiftBegStr) Then
        intStiftNeu = CLng(stiftBegStr)
    Else
        intStiftNeu = 0
    End If

    Dim r As Long, sCell As String, arr() As String
    For r = 3 To lngMaxRow
        If intColLSZ > 0 Then
            If InStr(1, LCase(ws.Cells(r, intColLSZ).Value), "zurue") > 0 Then GoTo NextRow
        End If

        sCell = ws.Cells(r, intColHvt).Value
        ' HVt-L hat Format Reihe/Leiste/Stift (3 Teile)
        If InStr(sCell, "/") = 0 Then GoTo NextRow
        arr = Split(sCell, "/")
        If UBound(arr) < 2 Then GoTo NextRow
        If arr(0) <> reiheAlt Or arr(1) <> leisteAlt Then GoTo NextRow

        Dim lR As Long, lL As Long, lRn As Long, lLn As Long, lSa As Long, lSn As Long
        lR = Len(arr(0)) : lL = Len(arr(1)) : lSa = Len(arr(2))
        lRn = Len(reiheNeu) : lLn = Len(leisteNeu) : lSn = Len(CStr(intStiftNeu))

        If intStiftNeu > 0 Then
            ws.Cells(r, intColHvt).Value = arr(0) & reiheNeu & "/" & arr(1) & leisteNeu & "/" & arr(2) & CStr(intStiftNeu)
        Else
            ws.Cells(r, intColHvt).Value = arr(0) & reiheNeu & "/" & arr(1) & leisteNeu & "/" & arr(2)
        End If

        Dim p As Long
        p = 1
        ws.Cells(r, intColHvt).Characters(Start:=p, Length:=lR).Font.Strikethrough = True
        p = p + lR
        With ws.Cells(r, intColHvt).Characters(Start:=p, Length:=lRn).Font
            .Strikethrough = False
            .Color = vbRed
        End With
        p = p + lRn + 1 ' '/'
        ws.Cells(r, intColHvt).Characters(Start:=p, Length:=lL).Font.Strikethrough = True
        p = p + lL
        With ws.Cells(r, intColHvt).Characters(Start:=p, Length:=lLn).Font
            .Strikethrough = False
            .Color = vbRed
        End With
        p = p + lLn + 1
        If intStiftNeu > 0 Then
            ws.Cells(r, intColHvt).Characters(Start:=p, Length:=lSa).Font.Strikethrough = True
            p = p + lSa
            With ws.Cells(r, intColHvt).Characters(Start:=p, Length:=lSn).Font
                .Strikethrough = False
                .Color = vbRed
            End With
            intStiftNeu = intStiftNeu + 1
        End If

        res.Anzahl = res.Anzahl + 1
        DoEvents
        If anzahlMax > 0 And res.Anzahl >= anzahlMax Then Exit For
NextRow:
    Next r

    ws.Columns(intColHvt).EntireColumn.AutoFit
    MergeAfterUmschaltung
    Application.DisplayAlerts = True
    Application.ScreenUpdating = True

    UmschaltenHvtL = res
End Function
