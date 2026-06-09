Attribute VB_Name = "Modul3"
Option Explicit

' v2.7 Modul3 bereinigt: Schaltzettel_Maximieren entfernt.
' func_MaxColumn / func_MaxRow bleiben - werden von SchaltzettelFormatieren
' und Modul_Umschaltung benoetigt.

Function func_MaxColumn(lngRow As Long) As Integer
    Dim intColAkt As Integer
    intColAkt = 1

    With ActiveWorkbook.Sheets("Schaltzettel")

        For intColAkt = 4 To 100
            If ActiveWorkbook.Sheets("Schaltzettel").Cells(lngRow, intColAkt).Value = "" Then
                func_MaxColumn = intColAkt - 1
                Exit Function
            End If
        Next intColAkt
    End With
End Function

Function func_MaxRow(intCol As Integer) As Long
    Dim lngRowAkt As Long
    lngRowAkt = 2

    With ActiveWorkbook.Sheets("Schaltzettel")

        For lngRowAkt = 3 To 10000
            If ActiveWorkbook.Sheets("Schaltzettel").Cells(lngRowAkt, intCol).Value = "" Then
                func_MaxRow = lngRowAkt - 1
                Exit Function
            End If
        Next lngRowAkt
    End With
End Function
