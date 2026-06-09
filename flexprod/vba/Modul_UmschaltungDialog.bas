Attribute VB_Name = "Modul_UmschaltungDialog"
Option Explicit

' v2.7 Eingabe-Dialog fuer Umschaltungen.
' Sequenz von InputBoxen ersetzt das alte frmUmschaltung. Vorteil:
' Anzahl-Stifte-Feld direkt mit drin, keine UserForm-Modifikation noetig.

Public Sub Umschaltung_Dialog_Anzeigen()
    Dim ws As Worksheet
    Set ws = ActiveWorkbook.Sheets("Schaltzettel")
    If ws.Cells(2, 4).Value = "" Then
        MsgBox "Kein Schaltzettel geladen. Bitte erst CSV importieren.", vbInformation
        Exit Sub
    End If

    Dim choice As String
    choice = InputBox( _
        "Welche Umschaltung?" & vbCrLf & vbCrLf & _
        "1 = HVt-L (Reihe/Leiste/Stift)" & vbCrLf & _
        "2 = EVS Stift an" & vbCrLf & _
        "3 = EVS Stift ab" & vbCrLf & _
        "4 = KVz", _
        "Umschaltung - Auswahl", "2")
    If choice = "" Then Exit Sub

    Select Case Trim(choice)
        Case "1": HvtLDialog
        Case "2": EvsDialog "Stift an"
        Case "3": EvsDialog "Stift ab"
        Case "4": KvzDialog
        Case Else
            MsgBox "Ungueltige Auswahl.", vbExclamation
    End Select
End Sub

Private Sub EvsDialog(ByVal headerKey As String)
    Dim evsAlt As String, evsNeu As String, stiftBeg As String, anzahlStr As String
    Dim kvzFilter As String

    evsAlt = InputBox("EVS Nr. alt (z.B. R8):", "Umschaltung " & headerKey)
    If evsAlt = "" Then Exit Sub
    If IsNumeric(evsAlt) Then
        MsgBox "EVS Nr. alt muss alphanumerisch sein (Buchstabe + Zahl), z.B. R8.", vbExclamation
        Exit Sub
    End If

    evsNeu = InputBox("EVS Nr. neu (z.B. R9):", "Umschaltung " & headerKey)
    If evsNeu = "" Then Exit Sub
    If IsNumeric(evsNeu) Then
        MsgBox "EVS Nr. neu muss alphanumerisch sein.", vbExclamation
        Exit Sub
    End If

    stiftBeg = InputBox( _
        "Stift-Beginnwert (numerisch)" & vbCrLf & _
        "Leer = ohne neue Stiftnummer (Stiftbezeichnung bleibt erhalten):", _
        "Umschaltung " & headerKey)
    If stiftBeg <> "" And Not IsNumeric(stiftBeg) Then
        MsgBox "Stift-Beginnwert muss numerisch sein.", vbExclamation
        Exit Sub
    End If

    anzahlStr = InputBox( _
        "Anzahl Stifte umschalten" & vbCrLf & _
        "(numerisch, z.B. 5 = nur 5 Stifte ab Beginnwert)" & vbCrLf & _
        "Leer oder 0 = alle passenden Stifte umschalten (Verhalten wie bisher):", _
        "Umschaltung " & headerKey)
    If anzahlStr <> "" And Not IsNumeric(anzahlStr) Then
        MsgBox "Anzahl Stifte muss numerisch sein.", vbExclamation
        Exit Sub
    End If

    kvzFilter = InputBox( _
        "KVz-Filter (optional)" & vbCrLf & _
        "Leer = keine KVz-Einschraenkung:", _
        "Umschaltung " & headerKey)

    Dim anzahlMax As Long
    If anzahlStr = "" Then
        anzahlMax = 0
    Else
        anzahlMax = CLng(anzahlStr)
    End If

    Dim res As UmschResult
    res = Modul_Umschaltung.UmschaltenStiftSpalte(headerKey, evsAlt, evsNeu, stiftBeg, anzahlMax, kvzFilter)
    If Not res.Abgebrochen Then
        MsgBox "Umschaltung '" & headerKey & "' bei " & res.Anzahl & " Leitungen durchgefuehrt." & vbCrLf & vbCrLf & _
               "Rueckgaengig moeglich via Button 'Letzte Umschaltung rueckgaengig machen'.", vbInformation
    End If
End Sub

Private Sub HvtLDialog()
    Dim reiheAlt As String, reiheNeu As String, leisteAlt As String, leisteNeu As String
    Dim stiftBeg As String, anzahlStr As String

    reiheAlt = InputBox("HVt-L: Reihe alt:", "HVt-L Umschaltung")
    If reiheAlt = "" Then Exit Sub
    reiheNeu = InputBox("HVt-L: Reihe neu:", "HVt-L Umschaltung")
    If reiheNeu = "" Then Exit Sub
    leisteAlt = InputBox("HVt-L: Leiste alt:", "HVt-L Umschaltung")
    If leisteAlt = "" Then Exit Sub
    leisteNeu = InputBox("HVt-L: Leiste neu:", "HVt-L Umschaltung")
    If leisteNeu = "" Then Exit Sub
    stiftBeg = InputBox("Stift-Beginnwert (leer = bleibt):", "HVt-L Umschaltung")
    If stiftBeg <> "" And Not IsNumeric(stiftBeg) Then
        MsgBox "Stift-Beginnwert muss numerisch sein.", vbExclamation
        Exit Sub
    End If
    anzahlStr = InputBox( _
        "Anzahl Stifte umschalten (leer/0 = alle):", _
        "HVt-L Umschaltung")
    If anzahlStr <> "" And Not IsNumeric(anzahlStr) Then
        MsgBox "Anzahl Stifte muss numerisch sein.", vbExclamation
        Exit Sub
    End If

    Dim anzahlMax As Long
    If anzahlStr = "" Then anzahlMax = 0 Else anzahlMax = CLng(anzahlStr)

    Dim res As UmschResult
    res = Modul_Umschaltung.UmschaltenHvtL(reiheAlt, reiheNeu, leisteAlt, leisteNeu, stiftBeg, anzahlMax)
    If Not res.Abgebrochen Then
        MsgBox "HVt-L Umschaltung bei " & res.Anzahl & " Leitungen durchgefuehrt." & vbCrLf & vbCrLf & _
               "Rueckgaengig moeglich via Button 'Letzte Umschaltung rueckgaengig machen'.", vbInformation
    End If
End Sub

Private Sub KvzDialog()
    Dim evsAlt As String, evsNeu As String, kvzFilter As String, stiftBeg As String, anzahlStr As String

    kvzFilter = InputBox("KVz-Bezeichnung (Filter, z.B. KVz-Nr.):", "KVz Umschaltung")
    If kvzFilter = "" Then
        MsgBox "KVz-Filter darf bei KVz-Umschaltung nicht leer sein.", vbExclamation
        Exit Sub
    End If
    evsAlt = InputBox("EVS Nr. alt:", "KVz Umschaltung")
    If evsAlt = "" Then Exit Sub
    evsNeu = InputBox("EVS Nr. neu:", "KVz Umschaltung")
    If evsNeu = "" Then Exit Sub
    stiftBeg = InputBox("Stift-Beginnwert (leer = bleibt):", "KVz Umschaltung")
    If stiftBeg <> "" And Not IsNumeric(stiftBeg) Then
        MsgBox "Stift-Beginnwert muss numerisch sein.", vbExclamation
        Exit Sub
    End If
    anzahlStr = InputBox( _
        "Anzahl Stifte umschalten (leer/0 = alle):", _
        "KVz Umschaltung")
    If anzahlStr <> "" And Not IsNumeric(anzahlStr) Then
        MsgBox "Anzahl Stifte muss numerisch sein.", vbExclamation
        Exit Sub
    End If

    Dim anzahlMax As Long
    If anzahlStr = "" Then anzahlMax = 0 Else anzahlMax = CLng(anzahlStr)

    Dim res As UmschResult
    res = Modul_Umschaltung.UmschaltenStiftSpalte("Stift ab", evsAlt, evsNeu, stiftBeg, anzahlMax, kvzFilter)
    If Not res.Abgebrochen Then
        MsgBox "KVz-Umschaltung bei " & res.Anzahl & " Leitungen durchgefuehrt." & vbCrLf & vbCrLf & _
               "Rueckgaengig moeglich via Button 'Letzte Umschaltung rueckgaengig machen'.", vbInformation
    End If
End Sub
