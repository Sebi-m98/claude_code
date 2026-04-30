Attribute VB_Name = "Modul_Export"
Option Explicit

' v2.7 PDF Export: aktuelle Schaltzettel-Ansicht als PDF, A4 quer,
' alle Spalten auf 1 Seite Breite (Hoehe darf mehrseitig sein).
Public Sub Schaltzettel_AlsPDF_Klicken()
    Dim ws As Worksheet
    Set ws = ActiveWorkbook.Sheets("Schaltzettel")

    Dim defaultName As String, fname As String, srcName As String
    On Error Resume Next
    srcName = ws.PageSetup.CenterHeader
    On Error GoTo 0
    If srcName = "" Or srcName = "CenterHeader" Then srcName = "Schaltzettel"
    defaultName = Replace(srcName, ".csv", "") & "_" & Format(Now, "yyyymmdd_hhnnss") & ".pdf"

    fname = Application.GetSaveAsFilename( _
        InitialFileName:=defaultName, _
        FileFilter:="PDF (*.pdf), *.pdf", _
        Title:="Schaltzettel als PDF speichern")
    If fname = False Or fname = "" Then Exit Sub

    Dim oldOrient As Long, oldZoom As Variant, oldFitW As Variant, oldFitH As Variant
    Dim oldArea As String

    Application.ScreenUpdating = False

    With ws.PageSetup
        oldOrient = .Orientation
        oldZoom = .Zoom
        oldFitW = .FitToPagesWide
        oldFitH = .FitToPagesTall
        oldArea = .PrintArea

        .Orientation = xlLandscape
        .PaperSize = xlPaperA4
        .Zoom = False
        .FitToPagesWide = 1
        .FitToPagesTall = False  ' Hoehe darf mehrseitig sein
        .LeftMargin = Application.InchesToPoints(0.3)
        .RightMargin = Application.InchesToPoints(0.3)
        .TopMargin = Application.InchesToPoints(0.5)
        .BottomMargin = Application.InchesToPoints(0.5)
        .HeaderMargin = Application.InchesToPoints(0.2)
        .FooterMargin = Application.InchesToPoints(0.2)
        ' Druckbereich: alle befuellten Spalten ab D
        Dim lastCol As Long, lastRow As Long
        lastCol = ws.Cells(2, ws.Columns.Count).End(xlToLeft).Column
        If lastCol < 4 Then lastCol = 4
        lastRow = ws.UsedRange.Rows.Count
        .PrintArea = ws.Range(ws.Cells(1, 4), ws.Cells(lastRow, lastCol)).Address
    End With

    On Error GoTo ExportFail
    ws.ExportAsFixedFormat _
        Type:=xlTypePDF, _
        Filename:=fname, _
        Quality:=xlQualityStandard, _
        IncludeDocProperties:=False, _
        IgnorePrintAreas:=False, _
        OpenAfterPublish:=False
    On Error GoTo 0

    With ws.PageSetup
        .Orientation = oldOrient
        If IsNumeric(oldZoom) Then .Zoom = oldZoom
        .FitToPagesWide = oldFitW
        .FitToPagesTall = oldFitH
        .PrintArea = oldArea
    End With

    Application.ScreenUpdating = True
    MsgBox "PDF gespeichert: " & vbCrLf & fname, vbInformation
    Exit Sub

ExportFail:
    Application.ScreenUpdating = True
    MsgBox "PDF-Export fehlgeschlagen: " & Err.Description, vbCritical
End Sub
