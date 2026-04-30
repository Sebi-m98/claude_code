VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
END
Attribute VB_Name = "Tabelle1"
Attribute VB_Base = "0{00020820-0000-0000-C000-000000000046}"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = True
Attribute VB_TemplateDerived = False
Attribute VB_Customizable = True

' v2.7 - bereinigtes Tabelle1: Sortieren-Button, Search&Replace BugFix und Leerzeilen-Funktion entfernt.
' SchaltzettelFormatieren bleibt mit impliziter Sortierung beim Import.
' Umschaltung_Klicken ruft die neue, kompakte UserForm auf.

Sub Umschaltung_Klicken()
    ' v2.7: ruft den neuen InputBox-Dialog (mit Anzahl-Stifte-Feld) auf.
    ' Das alte frmUmschaltung wird nicht mehr verwendet (kann geloescht werden).
    If ActiveWorkbook.Sheets("Schaltzettel").Cells(1, 1).Value = "" Then
        Modul_UmschaltungDialog.Umschaltung_Dialog_Anzeigen
    Else
        MsgBox "Umschaltung bereits durchgefuehrt."
    End If
End Sub

Sub Schaltzettel_Undo_Klicken()
    Modul_Umschaltung.Umschaltung_Undo
End Sub

Sub Schaltzettel_PDFExport_Klicken()
    Modul_Export.Schaltzettel_AlsPDF_Klicken
End Sub

Sub SchaltzettelFormatieren()
' v1.8 erstellt am 21.06.2016 von Sven Jelinski, TI NL West, PTI 11, PBB Doku
' Version mit Button + Optimierungen von Frank Klepec
' V 2.2 weitere Zellen mit gleichem Inhalt in Spalten E und F verbinden, R. Schmid, Team AI Süd Nbg.
' V 2.2 implizite Sortierung bei Import, neu mehrere Umschaltung-Funktionen, R. Schmid, Team AI Süd Nbg.


' ### Screenupdating AUS für Performance
'

'    Application.ScreenUpdating = False
    On Error GoTo Ende ' Bei Fehler an TextMarke Ende springen, damit Bildschirm wieder aktualisiert wird
    
    
' ############ Variablen für die neue Sortierfunktion, ReiSch, 08.12.20 #############
    Dim intCol, intMaxCol, intColEVSStiftAn, intColEVSStiftAb, intColEVSSort As Integer ' Zähler für Spalten, max. Anzahl Spalten, Spalte EVS ab
    Dim lngMaxRow, lngZahl As Long ' maximale Zeilen, eingefügte Zeilen, Zaehler für for-Schleifen

    Dim lAktRow, lStartRow As Long ' Aktuelle Zeile der inneren und Start-Zeile der äußeren schleife
    Dim lBegLtg As Long
    Dim lEndLtg As Long
    Dim lngEinfRow      ' Anzahl der zuverschiebenden Zeilen

    Dim lFirstRow, lFirstLSZ, lFirstKey As Long
    Dim strEVSSort As String
    Dim strEVSStift, strStift As String ' EVSbezeichnung und Stiftnr.
    Dim arrEVSStift() As String ' Bezeichnung EVS ab

    Dim intStiftNr, intStiftMin As Integer
    
    ' Variablen zum Löschen der AsB Nr aus Kvz und Apl
    Dim intColKVz, intColAPL As Integer
    Dim strAsbKvz, strAsbApl As String
    Dim arrAsbKvz() As String
    Dim arrAsbApl() As String
    Dim strKvz, strAPL As String
    
    ' Variablen, zum trennen von Strasse und Ort durch Zeilenumbruch
    Dim intColTAEAdr As Integer
    Dim strAdr, strStrasse, strOrt As String
    Dim arrAdr() As String
    
    ' Art des Schaltzettels EVs, KVZ etc.
    Dim strSchaltzTyp As String
    
    Dim blnCheck As Boolean ' Prüftbit, ob Sortierwert in Spalte Stift an oder ab existiert
    
' ######################################

' ###Datei auswählen
' ###Auswahlfenster um *.csv auszuwählen
'
    Dim V As String
    
    ' Variablen um aus Dateiname den relevanten EVS zu selektieren
    Dim arrPfad() As String
    Dim strDatei As String
    Dim arrDatei() As String
    Dim strEVS As String
    Dim strEVSBu, strEVSNr As String
    
    Dim dn As Variant ' dn definieren
        With Application.FileDialog(msoFileDialogFilePicker)
            .Filters.Add "Text Files", "*.csv", 1 'nur CSV auswählen und an 1. Stelle anzeigen
            If .Show = -1 Then 'prüfen ob eine Datei gewählt wurde
                V = .SelectedItems(1)
            Else
                MsgBox "Es wurde keine Datei gewählt!"
                Application.ScreenUpdating = True 'Bildschirmaktualisierung an
                Exit Sub 'Makro beenden
            End If
        End With
        
    arrPfad = Split(V, "\")
    If UBound(arrPfad) > 0 Then
        strDatei = arrPfad(UBound(arrPfad))
        arrDatei = Split(strDatei, "_")
        If UBound(arrDatei) > 0 Then
            If arrDatei(0) = "Schaltzettel" Then
                strSchaltzTyp = arrDatei(1)
'                MsgBox strDatei & " importieren."
                strKvz = arrDatei(4)
            Else
                MsgBox "Es wurde keine Schaltzettel-Datei gewählt!"
                Application.ScreenUpdating = True 'Bildschirmaktualisierung an
                Exit Sub 'Makro beenden
            End If
        End If
    End If
    
'
'
' ausgeblendete Spalten und Reihen einblenden
    With ActiveWorkbook.Sheets("Schaltzettel")
        .columns.Hidden = False
    End With

    With ActiveWorkbook.Sheets("Schaltzettel")
        .Rows.Hidden = False
    End With
    
' ###Alle Vorherigen Daten und Formatierungen löschen
    Cells.Clear
    ThisWorkbook.Sheets(1).PageSetup.PrintArea = "" ' Druckbereich aufheben für Performance
    ActiveSheet.ResetAllPageBreaks ' Zeilenumbrüche aufheben für Performance
    With ActiveSheet.PageSetup
        .CenterHeader = "CenterHeader" 'Center Kopfzeile leeren
        .LeftHeader = "LeftHeader" 'Linker Kopfzeilenbereich leeren
        .RightHeader = "RightHeader" 'rechter Kopfzeilenbereich leeren
    End With
    
    
'
' ### Bug Print_Area / Druckbereich ab Excel v2007
'

    With Print_Area_Bug_loesen
        On Error Resume Next
            ActiveWorkbook.Names("Print_Area").Delete
            ActiveWorkbook.Names("Print_Titles").Delete
        On Error GoTo 0
    End With
    
    
     Application.ScreenUpdating = False
    
    
' ###Einstellungen um CSV in MSDOS, Format und alle Spalten als TEXT formatiert zu importieren
    With ActiveSheet.QueryTables.Add(Connection:= _
        "TEXT;" & V _
        , Destination:=Range("$D$2"))
        .Name = V
        .FieldNames = True
        .RowNumbers = False
        .FillAdjacentFormulas = False
        .PreserveFormatting = True
        .RefreshOnFileOpen = False
        .RefreshStyle = xlInsertDeleteCells
        .SavePassword = False
        .SaveData = True
        .AdjustColumnWidth = True
        .RefreshPeriod = 0
        .TextFilePromptOnRefresh = False
        .TextFilePlatform = 1252 'MSDOS Code
        .TextFileStartRow = 1
        .TextFileParseType = xlDelimited
        .TextFileTextQualifier = xlTextQualifierDoubleQuote
        .TextFileConsecutiveDelimiter = False
        .TextFileTabDelimiter = True
        .TextFileSemicolonDelimiter = True
        .TextFileCommaDelimiter = True
        .TextFileSpaceDelimiter = False
        .TextFileColumnDataTypes = Array(2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2) 'Alle Spalten als TEXT
        .TextFileTrailingMinusNumbers = True
        .Refresh BackgroundQuery:=False
    End With
    
' ###Überprüfen ob Schaltzettel mit oder ohne neuen Führungen

    If Range("D1").Text = "Bestandsverschaltung" Then 'Wenn erfüllt, dann ist es ein Schaltzettel mit Neuen Führungen
'            MsgBox "Schaltzettel mit neuen Führungen"

' ###Leitungsbezn(Spalte 1, Zeile 4) zusammenfassen und Trennstriche einfügen,
' ###sowie erste Formatierungen
'
        ' Größe der Schaltzettel-Tabelle ermitteln
        
        intMaxCol = func_MaxColumn(2)
'        ActiveWorkbook.Sheets("Schaltzettel").UsedRange.Columns.Count
        lngMaxRow = ActiveWorkbook.Sheets("Schaltzettel").UsedRange.Rows.Count

        Const cCol As Long = 4              ' Gilt für Spalte-Nr.
        Dim lRow As Long, lFirstr As Long
        lRow = 4                            ' Gilt ab Zeile-Nr.
        lFirstr = lRow
        wechsel = 0
        With ActiveSheet
            Application.DisplayAlerts = False
            Do
                lRow = lRow + 1
                If .Cells(lRow, cCol) <> .Cells(lFirstr, cCol) Then
                .Range(.Cells(lRow - 1, cCol), .Cells(lFirstr, cCol + 25)).Select ' +25 bedeutet wie weit geht es nach rechts
                Selection.Borders(xlDiagonalDown).LineStyle = xlNone
                Selection.Borders(xlDiagonalUp).LineStyle = xlNone
                With Selection.Borders(xlEdgeLeft)
                    .LineStyle = xlContinuous
                    .ColorIndex = 0
                    .TintAndShade = 0
                    .Weight = xlThin
                End With
                With Selection.Borders(xlEdgeTop)
                    .LineStyle = xlContinuous
                    .ColorIndex = 0
                    .TintAndShade = 0
                    .Weight = xlThin
                End With
                With Selection.Borders(xlEdgeBottom)
                    .LineStyle = xlContinuous
                    .ColorIndex = 0
                    .TintAndShade = 0
                End With
' ###Überprüfen ob Datensatz gerade oder ungerade, dementsprechend hellgrau hinterlegen
                If wechsel Mod 2 <> 0 Then
                    .Range(.Cells(lRow - 1, cCol), .Cells(lFirstr, cCol + 25)).Select ' +25 bedeutet wie weit geht es nach rechts
                    With Selection.Interior
                    .Pattern = xlSolid
                    .PatternColorIndex = xlAutomatic
                    .ThemeColor = xlThemeColorDark1
                    .TintAndShade = -0.149998474074526
                    .PatternTintAndShade = 0
                    End With
                End If
                    .Range(.Cells(lRow - 1, cCol), .Cells(lFirstr, cCol)).Merge (False)
'                    .Range(.Cells(lRow - 1, cCol + 1), .Cells(lFirstR, cCol + 1)).Merge (False) ' weitere verbundene Zellen
                    lFirstr = lRow
' ###Zähler für gerade/ungerade Überprüfung um 1 erhöhen
                    wechsel = wechsel + 1
                End If
            Loop While .Cells(lRow, cCol) <> "Zielverschaltung"
            Application.DisplayAlerts = True
        End With
           
            
' ###Zweiter Schritt für Zielverschaltung
                Dim Zeile As Long
                Zeile = columns("D:D").Find(What:="Zielverschaltung").Row 'in Spalte D nach "Zielverschaltung suchen und sich die Zeile merken

' ###Leitungsbezn(Spalte 1, Zeile Variable "Zeile") zusammenfassen und Trennstriche einfügen,
' ###sowie Formatierungen
'

        'Const cCol As Long = 4              ' Gilt für Spalte-Nr.
        'Dim lRow As Long, lFirstR As Long
        lRow = Zeile + 3                          ' Gilt ab $Zeile + 3 nach unten
        lFirstr = lRow
        wechsel = 0
        With ActiveSheet
            Application.DisplayAlerts = False
            Do
                lRow = lRow + 1
                If .Cells(lRow, cCol) <> .Cells(lFirstr, cCol) Then
                    .Range(.Cells(lRow - 1, cCol), .Cells(lFirstr, cCol + 25)).Select ' +25 bedeutet wie weit geht es nach rechts
                    Selection.Borders(xlDiagonalDown).LineStyle = xlNone
                    Selection.Borders(xlDiagonalUp).LineStyle = xlNone
                    With Selection.Borders(xlEdgeLeft)
                        .LineStyle = xlContinuous
                        .ColorIndex = 0
                        .TintAndShade = 0
                        .Weight = xlThin
                    End With
                    With Selection.Borders(xlEdgeTop)
                        .LineStyle = xlContinuous
                        .ColorIndex = 0
                        .TintAndShade = 0
                        .Weight = xlThin
                    End With
                    With Selection.Borders(xlEdgeBottom)
                        .LineStyle = xlContinuous
                        .ColorIndex = 0
                        .TintAndShade = 0
                    End With
    ' ###Überprüfen ob Datensatz gerade oder ungerade, dementsprechend hellgrau hinterlegen
                    If wechsel Mod 2 <> 0 Then
                        .Range(.Cells(lRow - 1, cCol), .Cells(lFirstr, cCol + 25)).Select ' +25 bedeutet wie weit geht es nach rechts
                        With Selection.Interior
                        .Pattern = xlSolid
                        .PatternColorIndex = xlAutomatic
                        .ThemeColor = xlThemeColorDark1
                        .TintAndShade = -0.149998474074526
                        .PatternTintAndShade = 0
                        End With
                    End If
                    .Range(.Cells(lRow - 1, cCol), .Cells(lFirstr, cCol)).Merge (False)
'                    .Range(.Cells(lRow - 1, cCol + 1), .Cells(lFirstR, cCol + 1)).Merge (False) 'weitere verbundene Zellen
                    lFirstr = lRow
' ###Zähler für gerade/ungerade Überprüfung um 1 erhöhen
                    wechsel = wechsel + 1
                End If
            Loop While .Cells(lRow, cCol) <> ""
            Application.DisplayAlerts = True
        End With

'
' ###Tabelle formatieren
'

'
' ###Obersten Zeilen der beiden Bereiche Fett
        Rows("1:1").Font.Bold = True
        Rows("3:3").Font.Bold = True
        Rows(Zeile).Font.Bold = True
        Rows(Zeile + 2).Font.Bold = True

'
' ###Spalte D vertikal ausrichten
        
        With columns("D:D")
            .HorizontalAlignment = xlGeneral
            .VerticalAlignment = xlCenter
            .WrapText = False
            .Orientation = 0
            .AddIndent = False
            .IndentLevel = 0
            .ShrinkToFit = False
            .ReadingOrder = xlContext
        End With
    
' ###Spalte E horizontal ausrichten
        
        With columns("E:E")
            .HorizontalAlignment = xlCenter
            .VerticalAlignment = xlBottom
            .WrapText = False
            .Orientation = 0
            .AddIndent = False
            .IndentLevel = 0
            .ShrinkToFit = False
            .ReadingOrder = xlContext
            .MergeCells = False
        End With
    
' ###Ab Spalte V einen Trennstrich rechts einfügen
        
        With columns("V:V")
            .Borders(xlDiagonalDown).LineStyle = xlNone
            .Borders(xlDiagonalUp).LineStyle = xlNone
            .Borders(xlEdgeLeft).LineStyle = xlNone
            .Borders(xlEdgeTop).LineStyle = xlNone
            .Borders(xlEdgeBottom).LineStyle = xlNone
            .Borders(xlInsideVertical).LineStyle = xlNone
            .Borders(xlEdgeRight).LineStyle = xlContinuous
            .Borders(xlEdgeRight).ColorIndex = 0
            .Borders(xlEdgeRight).TintAndShade = 0
            .Borders(xlEdgeRight).Weight = xlThin

        End With
        
' ###Über Zeile mit Zielverschaltung zwei neue Zeilen einbringen
        Rows(Zeile).Insert Shift:=xlUp 'eine Zeile oberhalb einfügen
        Rows(Zeile).Insert Shift:=xlUp 'eine Zeile oberhalb einfügen
    
' ###Alle Zellen auf die korrekte Zellenbreite bringen und abschließend wieder A1 markieren
        Cells.EntireColumn.AutoFit
        Range("A1").Select
    
'
' ###Druckbereich festlegen
'
        With ActiveSheet.PageSetup
            .PrintTitleRows = "$3:$3" ' Auf jeder neuen Seite sollen die Spaltenüberschriften lesbar sein
            .PrintTitleColumns = ""
            .Orientation = xlLandscape
            dn = Dir(V) 'dn = Dateiname aus Pfad von V (selected Item);
            .CenterHeader = dn 'Center Kopfzeile mit Dateinamen versehen
            .LeftHeader = "&D" 'Linker Kopfzeilenbereich Datum
            .RightHeader = "Seite &P von &N" 'rechter Kopfzeilenbereich Seite x von y
        End With
        ActiveSheet.PageSetup.PrintArea = "$D:$V" ' Nur die Spalte D-V Drucken
    
' ###Über Zeile "Zielverschaltung" einen Druck-Umbruch erstellen
        Rows(Zeile).Select
        ActiveWindow.SelectedSheets.HPageBreaks.Add Before:=ActiveCell
        Rows("1:1").Select
        
' ###Zum Ende des Makros springen
        GoTo Ende
    
   

' ######################################################################


    Else 'hier die Alternative für keinen Bestandsführungsschaltzettel mit Überprüfung auf groß oder klein
    
    
' ######################################################################
    
        ' Größe der Schaltzettel-Tabelle ermitteln
        intMaxCol = func_MaxColumn(2)

'        intMaxCol = ActiveWorkbook.Sheets("Schaltzettel").UsedRange.Columns.Count
        lngMaxRow = ActiveWorkbook.Sheets("Schaltzettel").UsedRange.Rows.Count
    

' ###Überprüfen ob erweiterter Schaltzettel oder nicht

        If Range("AD2").Text <> "" Then 'Wenn erfüllt, dann ist es ein großer Schaltzettel
'            MsgBox "großer Schaltzettel"

' ########## Neue Sortierfunktion, nur bei Schaltzettelty EVs #####################################
    If UCase(strSchaltzTyp) = "EVS" Then

    '    Const cCol As Long = 4              ' Gilt für Spalte-Nr. Leitungsbezeichnung

            lAktRow = 2                           ' aktuelle Zeile-Nr. der Spaltenbezeichnungen
    
            lFirstRow = 1                      ' erste Zeilen-Nr. einer Leitung
    
            intColEVSStiftAn = 0
            intColEVSStiftAb = 0
    
            blnCheck = False
            
            strEVSBu = arrDatei(5)
            strEVSNr = arrDatei(6)
            strEVSSort = strEVSBu & strEVSNr    ' Sortierung nach EVS
            strEVS = ""
            
            ' Größe der Schaltzettel-Tabelle ermitteln
'            intMaxCol = ActiveWorkbook.Sheets("Schaltzettel").UsedRange.Columns.Count
'            lngMaxRow = ActiveWorkbook.Sheets("Schaltzettel").UsedRange.Rows.Count
    
        '        On Error GoTo Ende ' Bei Fehler an SprungMarke Ende springen
            
            ' und die Spalten-Nr. der EVS-Stifte an / ab ermitteln
    
            For intCol = 1 To intMaxCol + cCol Step 1
                If InStr(1, ActiveWorkbook.Sheets("Schaltzettel").Cells(lAktRow, intCol).Value, "Stift an") Then
                    If intColEVSStiftAn = 0 Then
                        intColEVSStiftAn = intCol
                        For lngZahl = 1 To lngMaxRow
                            strEVSStift = ActiveWorkbook.Sheets("Schaltzettel").Cells(lngZahl, intColEVSStiftAn).Value
                            arrEVSStift = Split(strEVSStift, "/") ' String auflösen in EVS und Stift
                            If UBound(arrEVSStift) > 0 Then
                                strEVS = arrEVSStift(LBound(arrEVSStift))
                                If strEVS = strEVSSort Then
                                    blnCheck = True
                                End If
                            End If
                        Next lngZahl
                    End If
                End If
            Next intCol
        
            If blnCheck Then
                intColEVSSort = intColEVSStiftAn
'                MsgBox " Es wird nach " & strEVSSort & " 'Stift an' aufsteigend sortiert."
        
                GoTo SortierungJa1
            Else
                For intCol = 1 To intMaxCol + cCol Step 1
                    If InStr(1, ActiveWorkbook.Sheets("Schaltzettel").Cells(lAktRow, intCol).Value, "Stift ab") Then
                        If intColEVSStiftAb = 0 Then
                            intColEVSStiftAb = intCol
                            For lngZahl = 1 To lngMaxRow
                                strEVSStift = ActiveWorkbook.Sheets("Schaltzettel").Cells(lngZahl, intColEVSStiftAb).Value
                                arrEVSStift = Split(strEVSStift, "/") ' String auflösen in EVS und Stift
                                If UBound(arrEVSStift) > 0 Then
                                    strEVS = arrEVSStift(LBound(arrEVSStift))
                                    If strEVS = strEVSSort Then
                                        blnCheck = True
                                    End If
                                End If
                            Next lngZahl
                        End If
                    End If
                Next intCol
            End If
            If blnCheck Then
                intColEVSSort = intColEVSStiftAb
'                MsgBox " Es wird nach " & strEVSSort & " 'Stift ab' aufsteigend sortiert."
        
                GoTo SortierungJa1
            Else
                GoTo SortierungNein1
            End If
            
SortierungJa1:
    
            lAktRow = 3 ' aktuelle Zeile-Nr. im Sortierdurchlauf
            lStartRow = 3 ' Start-Zeile für den nächsten Sortierdurchlauf
            lBegLtg = 0
            lEndLtg = 0
            lngEinfRow = 0
    
                Application.DisplayAlerts = False
        '
            With ActiveWorkbook.Sheets("Schaltzettel")
    
            ' äußere Schleife, Sortierschleife
                Do
                    lBegLtg = 0
                    lEndLtg = 0
                    lAktRow = lStartRow
                    lFirstRow = lStartRow - 1                    ' erste Zeilen-Nr. einer Leitung
                    strEVSStift = ""
                    strEVS = ""
                    strStift = ""
                    intStiftNr = 0
                    intStiftMin = 1000
    
                    ' innere Schleife, Suchschleife
    
                    Do
        '                lAktRow = lStartRow
                        ' Neue Leitungskey, Variable für erste Zeile einer Ltg.Bez. setzen
                        If .Cells(lAktRow, cCol) <> .Cells(lFirstRow, cCol) Then
                            lFirstRow = lAktRow
                        End If
    
                        strEVSStift = .Cells(lAktRow, intColEVSSort)
                        arrEVSStift = Split(strEVSStift, "/") ' String auflösen in EVS und Stift

                        If UBound(arrEVSStift) > 0 Then
                            strEVS = arrEVSStift(LBound(arrEVSStift))
                            strStift = arrEVSStift(UBound(arrEVSStift))
                            intStiftNr = Val(strStift)
                            If strEVS = strEVSSort Then
                                If intStiftMin > intStiftNr Then
                                    intStiftMin = intStiftNr
                                    lBegLtg = lFirstRow
    
                                    ' Wenn nach dem Suchkriterium gleich ein Wechsel erfolgt
                                    If .Cells(lAktRow + 1, cCol) <> .Cells(lBegLtg, cCol) Then
                                        lEndLtg = lAktRow
                                    Else
    
                                    ' Wenn nach dem Suchkriterium die Leitung gleich bleibt
                                        Do
                                            lAktRow = lAktRow + 1
                                        Loop While .Cells(lAktRow, cCol) = .Cells(lBegLtg, cCol)
                                        lAktRow = lAktRow - 1
                                        lEndLtg = lAktRow
    
                                    End If
                                End If
                            End If
                        End If
                        lAktRow = lAktRow + 1
    
                    Loop While .Cells(lAktRow, cCol) <> ""
    
                    ' wenn Variablen > 0 wurde ein entsprechender EVS mit minimaler StiftNr. in dieser Ltg. gefunden
                    If lBegLtg > 0 And lEndLtg > 0 Then
                        ' Ltg mit minimaler Stiftnr. an Startposition einfügen
                        lngEinfRow = lEndLtg - lBegLtg + 1
                        For lngZahl = 1 To lngEinfRow
                            .Rows(lStartRow & ":" & lStartRow).Insert Shift:=xlDown
                        Next lngZahl
                        .Range(.Cells(lBegLtg + lngEinfRow, cCol), Cells(lEndLtg + lngEinfRow, intMaxCol + cCol)).Copy Destination:=.Cells(lStartRow, 4)
                        .Rows(lBegLtg + lngEinfRow & ":" & lEndLtg + lngEinfRow).Delete Shift:=xlUp
                        DoEvents
                    End If
    
                    ' nach der Einfügezeile fortfahren und die nächste minimale Stiftnr. ermitteln
                    lStartRow = lStartRow + lngEinfRow
    
                Loop While lStartRow < lngMaxRow
    
            End With
            
SortierungNein1:
    
            Application.DisplayAlerts = True
    End If
' ########### Ende Sortierfunktion ###############


' ###Leitungsbezn(Spalte 1, Zeile 4) zusammenfassen und Trennstriche einfügen,
' ###sowie erste Formatierungen
'
            ' Größe der Schaltzettel-Tabelle ermitteln
            intMaxCol = func_MaxColumn(2)

'            intMaxCol = ActiveWorkbook.Sheets("Schaltzettel").UsedRange.Columns.Count
            lngMaxRow = ActiveWorkbook.Sheets("Schaltzettel").UsedRange.Rows.Count

            'Const cCol As Long = 4              ' Gilt für Spalte-Nr.
            'Dim lRow As Long, lFirstR As Long
            lRow = 3                            ' Gilt ab Zeile-Nr.
            lFirstr = lRow
            lFirstLSZ = 3
            lFirstKey = 3
            wechsel = 0
            
            With ActiveSheet
                Application.DisplayAlerts = False
                Do
                    lRow = lRow + 1
                    If .Cells(lRow, cCol) <> .Cells(lFirstr, cCol) Then
                        .Range(.Cells(lRow - 1, cCol), .Cells(lFirstr, intMaxCol)).Select ' wie weit geht es nach rechts
                        Selection.Borders(xlDiagonalDown).LineStyle = xlNone
                        Selection.Borders(xlDiagonalUp).LineStyle = xlNone
                        With Selection.Borders(xlEdgeLeft)
                            .LineStyle = xlContinuous
                            .ColorIndex = 0
                            .TintAndShade = 0
                            .Weight = xlThin
                        End With
                        With Selection.Borders(xlEdgeTop)
                            .LineStyle = xlContinuous
                            .ColorIndex = 0
                            .TintAndShade = 0
                            .Weight = xlThin
                        End With
                        With Selection.Borders(xlEdgeBottom)
                            .LineStyle = xlContinuous
                            .ColorIndex = 0
                            .TintAndShade = 0
                        End With
                        With Selection.Borders(xlEdgeRight)
                            .LineStyle = xlContinuous
                            .ColorIndex = 0
                            .TintAndShade = 0
                        End With
' ###Überprüfen ob Datensatz gerade oder ungerade, dementsprechend hellgrau hinterlegen
                        If wechsel Mod 2 <> 0 Then
                            .Range(.Cells(lRow - 1, cCol), .Cells(lFirstr, intMaxCol)).Select ' wie weit geht es nach rechts
                            With Selection.Interior
                            .Pattern = xlSolid
                            .PatternColorIndex = xlAutomatic
                            .ThemeColor = xlThemeColorDark1
                            .TintAndShade = -0.149998474074526
                            .PatternTintAndShade = 0
                            End With
                        End If
                        
                        ' gleiche Leitungskey verbinden
                        .Range(.Cells(lRow - 1, cCol + 2), .Cells(lFirstKey, cCol + 2)).Merge (False) 'weitere verbundene Zellen

                        ' gleiche LSZ Verbinden
                        .Range(.Cells(lRow - 1, cCol + 1), .Cells(lFirstLSZ, cCol + 1)).Merge (False) 'weitere verbundene Zellen
                        
                        ' gleiche Leitungsbez. verbinden
                        .Range(.Cells(lRow - 1, cCol), .Cells(lFirstr, cCol)).Merge (False)

                        lFirstLSZ = lRow
                        lFirstKey = lRow
                        lFirstr = lRow
                        
' ###Zähler für gerade/ungerade Überprüfung um 1 erhöhen
                        wechsel = wechsel + 1
                       
                    Else
                    
                    ' Wechsel der LSZ  bzw. Leitungskey bei gleicher Leitungsbez
                        If .Cells(lRow, cCol + 1) <> .Cells(lFirstLSZ, cCol + 1) Then
                            .Range(.Cells(lRow - 1, cCol + 1), .Cells(lFirstLSZ, cCol + 1)).Merge (False) 'weitere verbundene Zellen
                            lFirstLSZ = lRow
                        End If
                        
                        ' Wechsel des Leitungskey bei gleicher Leitungsbez
                        If .Cells(lRow, cCol + 2) <> .Cells(lFirstKey, cCol + 2) Then
                            .Range(.Cells(lRow - 1, cCol + 2), .Cells(lFirstKey, cCol + 2)).Merge (False) 'weitere verbundene Zellen
                            lFirstKey = lRow
                        End If
                        
                    End If
                Loop While .Cells(lRow, cCol) <> ""
                Application.DisplayAlerts = True
            End With
'
' ###Tabelle formatieren
'

'
' ###Oberste Zeile Fett
            Rows("2:2").Font.Bold = True

'
' ###Spalte D vertikal ausrichten
        
            With columns("D:D")
                .HorizontalAlignment = xlGeneral
                .VerticalAlignment = xlCenter
                .WrapText = False
                .Orientation = 0
                .AddIndent = False
                .IndentLevel = 0
                .ShrinkToFit = False
                .ReadingOrder = xlContext
            End With
    
' ###Spalte E nun vertikal ausrichten bei verbunden
        
            With columns("E:E")
    '            .HorizontalAlignment = xlCenter
    '            .VerticalAlignment = xlBottom
                .HorizontalAlignment = xlGeneral
                .VerticalAlignment = xlCenter
                .WrapText = False
                .Orientation = 0
                .AddIndent = False
                .IndentLevel = 0
                .ShrinkToFit = False
                .ReadingOrder = xlContext
    '            .MergeCells = False
            End With
            
 ' ###Spalte F vertikal ausrichten
        
            With columns("F:F")
                .HorizontalAlignment = xlGeneral
                .VerticalAlignment = xlCenter
                .WrapText = False
                .Orientation = 0
                .AddIndent = False
                .IndentLevel = 0
                .ShrinkToFit = False
                .ReadingOrder = xlContext
            End With
   
' ###Ab Spalte AR einen Trennstrich rechts einfügen
        
'            With Columns("BE:BE")
'                .Borders(xlDiagonalDown).LineStyle = xlNone
'                .Borders(xlDiagonalUp).LineStyle = xlNone
'                .Borders(xlEdgeLeft).LineStyle = xlNone
'                .Borders(xlEdgeTop).LineStyle = xlNone
'                .Borders(xlEdgeBottom).LineStyle = xlNone
'                .Borders(xlInsideVertical).LineStyle = xlNone
'                .Borders(xlEdgeRight).LineStyle = xlContinuous
'                .Borders(xlEdgeRight).ColorIndex = 0
'                .Borders(xlEdgeRight).TintAndShade = 0
'                .Borders(xlEdgeRight).Weight = xlThin
'
'            End With
        
    
' ###Alle Zellen auf die korrekte Zellenbreite bringen und abschließend wieder A1 markieren
            Cells.EntireColumn.AutoFit
            Range("A2").Select
    
'
' ###Druckbereich festlegen
'
            With ActiveSheet.PageSetup
                .PrintTitleRows = "$2:$2" ' Auf jeder neuen Seite sollen die Spaltenüberschriften lesbar sein
                .PrintTitleColumns = ""
                .Orientation = xlLandscape
                dn = Dir(V) 'dn = Dateiname aus Pfad von V (selected Item);
                .CenterHeader = dn 'Center Kopfzeile mit Dateinamen versehen
                .LeftHeader = "&D" 'Linker Kopfzeilenbereich Datum
                .RightHeader = "Seite &P von &N" 'rechter Kopfzeilenbereich Seite x von y
            End With
            ActiveSheet.PageSetup.PrintArea = "$D:$BE" ' Nur die Spalte D-BE Drucken
    
   
   

' ######################################################################


        Else 'hier die Alternative für kleinen Schaltzettel
'            MsgBox "kleiner Schaltzettel"

            ' Größe der Schaltzettel-Tabelle ermitteln
            intMaxCol = func_MaxColumn(2)

'            intMaxCol = ActiveWorkbook.Sheets("Schaltzettel").UsedRange.Columns.Count
            lngMaxRow = ActiveWorkbook.Sheets("Schaltzettel").UsedRange.Rows.Count

    
' ######################################################################

' ########## Neue Sortierfunktion #####################################
    If UCase(strSchaltzTyp) = "EVS" Then
        
            '
            '    Const cCol As Long = 4              ' Gilt für Spalte-Nr. Leitungsbezeichnung
        
            lAktRow = 2                           ' aktuelle Zeile-Nr. der Spaltenbezeichnungen
        
            lFirstRow = 1                      ' erste Zeilen-Nr. einer Leitung
        
            intColEVSStiftAn = 0
        
            intColEVSStiftAb = 0
        
            blnCheck = False
            
            strEVSBu = arrDatei(5)
            strEVSNr = arrDatei(6)
            strEVSSort = strEVSBu & strEVSNr  ' Sortierung nach EVS
            strEVS = ""
        
            ' Größe der Schaltzettel-Tabelle ermitteln
'            intMaxCol = ActiveWorkbook.Sheets("Schaltzettel").UsedRange.Columns.Count
'            lngMaxRow = ActiveWorkbook.Sheets("Schaltzettel").UsedRange.Rows.Count
            
            '        On Error GoTo Ende ' Bei Fehler an SprungMarke Ende springen
        
            ' und die Spalten-Nr. der EVS-Stifte an / ab ermitteln
            For intCol = 1 To intMaxCol + cCol Step 1
                If InStr(1, ActiveWorkbook.Sheets("Schaltzettel").Cells(lAktRow, intCol).Value, "Stift an") Then
                    If intColEVSStiftAn = 0 Then
                        intColEVSStiftAn = intCol
                        For lngZahl = 1 To lngMaxRow
                            strEVSStift = ActiveWorkbook.Sheets("Schaltzettel").Cells(lngZahl, intColEVSStiftAn).Value
                            arrEVSStift = Split(strEVSStift, "/") ' String auflösen in EVS und Stift
                            If UBound(arrEVSStift) > 0 Then
                                strEVS = arrEVSStift(LBound(arrEVSStift))
                                If strEVS = strEVSSort Then
                                    blnCheck = True
                                End If
                            End If
                        
                        Next lngZahl
                    End If
                End If
            Next intCol
        
            If blnCheck Then
                intColEVSSort = intColEVSStiftAn
'                MsgBox " Es wird nach " & strEVSSort & " 'Stift an' aufsteigend sortiert."
        
                GoTo SortierungJa2
            Else
                For intCol = 1 To intMaxCol + cCol Step 1
                    If InStr(1, ActiveWorkbook.Sheets("Schaltzettel").Cells(lAktRow, intCol).Value, "Stift ab") Then
                        If intColEVSStiftAb = 0 Then
                            intColEVSStiftAb = intCol
                            For lngZahl = 1 To lngMaxRow
                                strEVSStift = ActiveWorkbook.Sheets("Schaltzettel").Cells(lngZahl, intColEVSStiftAb).Value
                                arrEVSStift = Split(strEVSStift, "/") ' String auflösen in EVS und Stift
                                If UBound(arrEVSStift) > 0 Then
                                    strEVS = arrEVSStift(LBound(arrEVSStift))
                                    If strEVS = strEVSSort Then
                                        blnCheck = True
                                    End If
                                End If
                            
                            Next lngZahl
                        End If
                    End If
                Next intCol
            End If
            If blnCheck Then
                intColEVSSort = intColEVSStiftAb
'                MsgBox " Es wird nach " & strEVSSort & " 'Stift ab' aufsteigend sortiert."
        
                GoTo SortierungJa2
            Else
                GoTo SortierungNein2
            End If
            
SortierungJa2:
        
            lAktRow = 3 ' aktuelle Zeile-Nr. im Sortierdurchlauf
            lStartRow = 3 ' Start-Zeile für den nächsten Sortierdurchlauf
            lBegLtg = 0
            lEndLtg = 0
            lngEinfRow = 0
    
            Application.DisplayAlerts = False
        
            With ActiveWorkbook.Sheets("Schaltzettel")
    
            ' äußere Schleife, Sortierschleife
                Do
                    lBegLtg = 0
                    lEndLtg = 0
                    lAktRow = lStartRow
                    lFirstRow = lStartRow - 1                    ' erste Zeilen-Nr. einer Leitung
                    strEVSStift = ""
                    strEVS = ""
                    strStift = ""
                    intStiftNr = 0
                    intStiftMin = 1000
    
                    ' innere Schleife, Suchschleife
    
                    Do
        '                lAktRow = lStartRow
                        ' Neue Leitungskey, Variable für erste Zeile einer Ltg.Bez. setzen
                        If .Cells(lAktRow, cCol) <> .Cells(lFirstRow, cCol) Then
                            lFirstRow = lAktRow
                        End If
    
                        strEVSStift = .Cells(lAktRow, intColEVSSort)
                        arrEVSStift = Split(strEVSStift, "/") ' String auflösen in EVS und Stift

                        If UBound(arrEVSStift) > 0 Then
                            strEVS = arrEVSStift(LBound(arrEVSStift))
                            strStift = arrEVSStift(UBound(arrEVSStift))
                            intStiftNr = Val(strStift)
                            If strEVS = strEVSSort Then
                                If intStiftMin > intStiftNr Then
                                    intStiftMin = intStiftNr
                                    lBegLtg = lFirstRow

                                    ' Wenn nach dem Suchkriterium gleich ein Wechsel erfolgt
                                    If .Cells(lAktRow + 1, cCol) <> .Cells(lBegLtg, cCol) Then
                                        lEndLtg = lAktRow
    '                                    MsgBox intStiftMin & " Beg " & lBegLtg & " End " & lEndLtg
                                    Else

                                    ' Wenn nach dem Suchkriterium die Leitung gleich bleibt
                                        Do
                                            lAktRow = lAktRow + 1
                                        Loop While .Cells(lAktRow, cCol) = .Cells(lBegLtg, cCol)
                                        lAktRow = lAktRow - 1
                                        lEndLtg = lAktRow

    '                                    MsgBox intStiftMin & " Beg " & lBegLtg & " End " & lEndLtg
                                    End If
                                End If
                            End If
                        End If
                        lAktRow = lAktRow + 1
    
                    Loop While .Cells(lAktRow, cCol) <> ""
    
                    ' wenn Variablen > 0 wurde ein entsprechender EVS mit minimaler StiftNr. in dieser Ltg. gefunden
                    If lBegLtg > 0 And lEndLtg > 0 Then
                        ' Ltg mit minimaler Stiftnr. an Startposition einfügen
                        lngEinfRow = lEndLtg - lBegLtg + 1
                        For lngZahl = 1 To lngEinfRow
                            .Rows(lStartRow & ":" & lStartRow).Insert Shift:=xlDown
                        Next lngZahl
        '                MsgBox "Einfügen: " & intStiftMin & " Beg " & lBegLtg & " End " & lEndLtg
                        .Range(.Cells(lBegLtg + lngEinfRow, cCol), Cells(lEndLtg + lngEinfRow, intMaxCol + cCol)).Copy Destination:=.Cells(lStartRow, 4)
                        .Rows(lBegLtg + lngEinfRow & ":" & lEndLtg + lngEinfRow).Delete Shift:=xlUp
                        
                        DoEvents
                    End If
    
                    ' nach der Einfügezeile fortfahren und die nächste minimale Stiftnr. ermitteln
                    lStartRow = lStartRow + lngEinfRow
    
                Loop While lStartRow < lngMaxRow
    
            End With
    
SortierungNein2:
    
            Application.DisplayAlerts = True
    End If

' ########### Ende Sortierfunktion ###############
    
   
'
' ###Leitungsbezn(Spalte 1, Zeile 2) zusammenfassen und Trennstriche einfügen,
' ###sowie erste Formatierungen
'

            ' Größe der Schaltzettel-Tabelle ermitteln
            intMaxCol = func_MaxColumn(2)

'            intMaxCol = ActiveWorkbook.Sheets("Schaltzettel").UsedRange.Columns.Count
            lngMaxRow = ActiveWorkbook.Sheets("Schaltzettel").UsedRange.Rows.Count
            
            lRow = 3                            ' Gilt ab Zeile-Nr.
            lFirstr = lRow
            lFirstLSZ = 3
            wechsel = 0
            With ActiveSheet
                Application.DisplayAlerts = False
                Do
                    lRow = lRow + 1
                    If .Cells(lRow, cCol) <> .Cells(lFirstr, cCol) Then
                        .Range(.Cells(lRow - 1, cCol), .Cells(lFirstr, intMaxCol)).Select ' +25 bedeutet wie weit geht es nach rechts
                        Selection.Borders(xlDiagonalDown).LineStyle = xlNone
                        Selection.Borders(xlDiagonalUp).LineStyle = xlNone
                        With Selection.Borders(xlEdgeLeft)
                            .LineStyle = xlContinuous
                            .ColorIndex = 0
                            .TintAndShade = 0
                            .Weight = xlThin
                        End With
                        With Selection.Borders(xlEdgeTop)
                            .LineStyle = xlContinuous
                            .ColorIndex = 0
                            .TintAndShade = 0
                            .Weight = xlThin
                        End With
                        With Selection.Borders(xlEdgeBottom)
                            .LineStyle = xlContinuous
                            .ColorIndex = 0
                            .TintAndShade = 0
                        End With
                        With Selection.Borders(xlEdgeRight)
                            .LineStyle = xlContinuous
                            .ColorIndex = 0
                            .TintAndShade = 0
                        End With

            
' ###Überprüfen ob Datensatz gerade oder ungerade, dementsprechend hellgrau hinterlegen
                        If wechsel Mod 2 <> 0 Then
                            .Range(.Cells(lRow - 1, cCol), .Cells(lFirstr, intMaxCol)).Select ' +25 bedeutet wie weit geht es nach rechts
                            With Selection.Interior
                            .Pattern = xlSolid
                            .PatternColorIndex = xlAutomatic
                            .ThemeColor = xlThemeColorDark1
                            .TintAndShade = -0.149998474074526
                            .PatternTintAndShade = 0
                            End With
                        End If
                        
                        ' gleiche LSZ Verbinden
                        .Range(.Cells(lRow - 1, cCol + 1), .Cells(lFirstLSZ, cCol + 1)).Merge (False) 'weitere verbundene Zellen
                        
                        ' gleiche Leitungsbez. verbinden
                        .Range(.Cells(lRow - 1, cCol), .Cells(lFirstr, cCol)).Merge (False)

                        lFirstLSZ = lRow
                        lFirstr = lRow
                        
' ###Zähler für gerade/ungerade Überprüfung um 1 erhöhen
                        wechsel = wechsel + 1
                       
                    Else
                    ' Wechsel der LSZ bei gleicher Leitung
                        If .Cells(lRow, cCol + 1) <> .Cells(lFirstLSZ, cCol + 1) Then
                            .Range(.Cells(lRow - 1, cCol + 1), .Cells(lFirstLSZ, cCol + 1)).Merge (False) 'weitere verbundene Zellen
                            lFirstLSZ = lRow
                    
                        End If
                    End If
                Loop While .Cells(lRow, cCol) <> ""
                Application.DisplayAlerts = True
            End With


'
' ###Tabelle formatieren
'

'
' ###Oberste Zeile Fett
            Rows("2:2").Font.Bold = True

'
' ###Spalte D vertikal ausrichten
        
            With columns("D:D")
                .HorizontalAlignment = xlGeneral
                .VerticalAlignment = xlCenter
                .WrapText = False
                .Orientation = 0
                .AddIndent = False
                .IndentLevel = 0
                .ShrinkToFit = False
                .ReadingOrder = xlContext
            End With
    
' ###Spalte E nun vertikal ausrichten
        
            With columns("E:E")
    '            .HorizontalAlignment = xlCenter
    '            .VerticalAlignment = xlBottom
                .HorizontalAlignment = xlGeneral
                .VerticalAlignment = xlCenter
    
                .WrapText = False
                .Orientation = 0
                .AddIndent = False
                .IndentLevel = 0
                .ShrinkToFit = False
                .ReadingOrder = xlContext
    '            .MergeCells = False
            End With
    
' ###Ab Spalte AC einen Trennstrich rechts einfügen
        
'            With Columns("AC:AC")
'                .Borders(xlDiagonalDown).LineStyle = xlNone
'                .Borders(xlDiagonalUp).LineStyle = xlNone
'                .Borders(xlEdgeLeft).LineStyle = xlNone
'                .Borders(xlEdgeTop).LineStyle = xlNone
'                .Borders(xlEdgeBottom).LineStyle = xlNone
'                .Borders(xlInsideVertical).LineStyle = xlNone
'                .Borders(xlEdgeRight).LineStyle = xlContinuous
'                .Borders(xlEdgeRight).ColorIndex = 0
'                .Borders(xlEdgeRight).TintAndShade = 0
'                .Borders(xlEdgeRight).Weight = xlThin
'
'            End With
        
    
' ###Alle Zellen auf die korrekte Zellenbreite bringen und abschließend wieder A1 markieren
            Cells.EntireColumn.AutoFit
            Range("A2").Select
    
'
' ###Druckbereich festlegen
'

            With ActiveSheet.PageSetup
                .PrintTitleRows = "$2:$2" ' Auf jeder neuen Seite sollen die Spaltenüberschriften lesbar sein
                .PrintTitleColumns = ""
                .Orientation = xlLandscape
            End With
            ActiveSheet.PageSetup.PrintArea = "$D:$AC" ' Nur die Spalte D-AC Drucken
                dn = Dir(V) 'dn = Dateiname aus Pfad von V (selected Item);
            With ActiveSheet.PageSetup
                .Zoom = False
                .FitToPagesWide = 1 ' Auf breite "eine Seite" festlegen
                .FitToPagesTall = False
                .CenterHeader = dn 'Center Kopfzeile mit Dateinamen versehen
                .LeftHeader = "&D" 'Linker Kopfzeilenbereich Datum
                .RightHeader = "Seite &P von &N" 'rechter Kopfzeilenbereich Seite x von y
            End With
        End If
        
    End If
    
' ############## Asb aus Kvz und Apl entfernen #############

' die Variabeln initialisieren
    lAktRow = 2
    intColKVz = 0
    intColAPL = 0
    strAsbKvz = ""
    strAsbApl = ""
    intMaxCol = func_MaxColumn(2)

'    intMaxCol = ActiveWorkbook.Sheets("Schaltzettel").UsedRange.Columns.Count
    lngMaxRow = ActiveWorkbook.Sheets("Schaltzettel").UsedRange.Rows.Count
    
' die Spalten-Nr. von Kvz und Apl ermitteln
    For intCol = 1 To intMaxCol + cCol Step 1
        If InStr(1, LCase(ActiveWorkbook.Sheets("Schaltzettel").Cells(lAktRow, intCol).Value), "kvz") Then
            If intColKVz = 0 Then
                intColKVz = intCol
            End If
        End If
        If InStr(1, LCase(ActiveWorkbook.Sheets("Schaltzettel").Cells(lAktRow, intCol).Value), "apl") Then
            If intColAPL = 0 Then
                intColAPL = intCol
            End If
        End If
    Next intCol
    
    
 ' prüfen ob Spalte Apl gefunden > 0 und "/" vorhanden
    If intColAPL > 0 Then
        lRow = 3                            ' Gilt ab Zeile-Nr.
        With ActiveSheet
            Application.DisplayAlerts = False
            For lRow = 3 To lngMaxRow
                If .Cells(lRow, intColAPL) <> "" Then ' Falls leer, Zelle überspringen
                    If InStr(1, .Cells(lRow, intColAPL), "/") Then
                        strAsbApl = .Cells(lRow, intColAPL)
                        arrAsbApl = Split(strAsbApl, "/") ' String auflösen in Asb und Apl
                        If UBound(arrAsbApl) > 0 Then
                            strAPL = arrAsbApl(UBound(arrAsbApl))
                            .Cells(lRow, intColAPL) = strAPL
                        End If
                    End If
                End If
            Next lRow
            Application.DisplayAlerts = True
        End With
    End If

' Falls Spalte TAE Adresse vorhanden, einen Zeilenumbruch zwischen Strasse und Ort einfügen
    intColTAEAdr = 0
    
    For intCol = 1 To intMaxCol Step 1
        If InStr(1, LCase(ActiveWorkbook.Sheets("Schaltzettel").Cells(lAktRow, intCol).Value), "tae adresse") Then
            If intColTAEAdr = 0 Then
                intColTAEAdr = intCol
            End If
        End If
    Next intCol
    
    If intColTAEAdr > 0 Then
        lRow = 3                            ' Gilt ab Zeile-Nr.
        With ActiveSheet
            For lRow = 3 To lngMaxRow
                If .Cells(lRow, intColTAEAdr) <> "" Then ' Falls leer, Zelle überspringen
                    If InStr(1, .Cells(lRow, intColTAEAdr), ",") Then
                        strAdr = .Cells(lRow, intColTAEAdr)
                        arrAdr = Split(strAdr, ",") ' String auflösen in Strasse und Ort
                        If UBound(arrAdr) > 0 Then
                            strOrt = Trim(arrAdr(UBound(arrAdr)))
                            strStrasse = Trim(arrAdr(LBound(arrAdr)))
                            .Cells(lRow, intColTAEAdr).FormulaR1C1 = strStrasse & "," & Chr(10) & strOrt
'                            .Cells(lRow, intColTaeAdr) = strStrasse & ", " & vbCr & strOrt
                        End If
                        
                    End If
                End If
            Next lRow
        End With
    End If
    ' Sperre für Umschaltung aufheben
'    ActiveSheet.Range("A1") = ""
'    With ActiveSheet.Range("A1").Font
'        .ThemeColor = xlThemeColorDark1
'        .TintAndShade = 0
'    End With
    Application.ScreenUpdating = True
    ActiveSheet.Range("D3").Select
'    MsgBox "CSV erfolgreich importiert"
    Exit Sub
'
' ### Textmarke ENDE
'

Ende:
    Application.ScreenUpdating = True

End Sub
