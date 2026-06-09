#!/usr/bin/env python3
"""
Build the optimized FlexProdSchaltzettel v2.7 xlsm.

Steps performed:
- Strip workbookProtection from xl/workbook.xml
- Remove 5 unwanted buttons (Sortieren, Min, Max, Search&Replace, Leerzeile)
  from xl/drawings/vmlDrawing1.vml, xl/worksheets/sheet1.xml controls block,
  xl/worksheets/_rels/sheet1.xml.rels and the corresponding ctrlPropX.xml files.
- Modify the Zurue Ltg. button label to indicate the new toggle behavior.
- Add 2 new buttons (PDF Export, Letzte Umschaltung rueckgaengig) with new
  ctrlPropX.xml + rels + sheet1.xml control entries.
- Update sheet2 (Anleitung) and Changelog (sheet3) text via sharedStrings.xml.
- VBA: this script does NOT modify vbaProject.bin. The user imports the new
  .bas/.cls files via Excel VBA Editor.

Output: build/FlexProdSchaltzettel_v2.7.xlsm
"""
import os
import re
import shutil
import zipfile
import sys
from pathlib import Path

ROOT = Path(__file__).parent
BUILD = ROOT / "build"
SRC = BUILD / "src"
OUT = BUILD / "FlexProdSchaltzettel_v2.7.xlsm"

REMOVE_BUTTONS = {
    # shapeId -> (rId, ctrlProp number)
    "1030": ("rId6", 3),  # Sortierung
    "1032": ("rId8", 5),  # Minimieren
    "1033": ("rId9", 6),  # Maximieren
    "1036": ("rId10", 7),  # Search&Replace
    "1037": ("rId11", 8),  # Leerzeile
}


def reset_src():
    """Re-extract original xlsm into build/src for a clean build."""
    if SRC.exists():
        shutil.rmtree(SRC)
    SRC.mkdir(parents=True)
    with zipfile.ZipFile(ROOT / "FlexProdSchaltzettel.xlsm") as zf:
        zf.extractall(SRC)
    print(f"  reset {SRC}")


def strip_workbook_protection():
    p = SRC / "xl/workbook.xml"
    c = p.read_text(encoding="utf-8")
    c2 = re.sub(r"<workbookProtection [^/]*/>", "", c)
    assert c != c2, "workbookProtection not found"
    p.write_text(c2, encoding="utf-8")
    print("  workbookProtection removed")


def patch_vml():
    """Remove 5 unwanted shapes, modify Zurue label, add 2 new shapes."""
    p = SRC / "xl/drawings/vmlDrawing1.vml"
    c = p.read_text(encoding="utf-8")

    # Find each <v:shape ...>...</v:shape> block; remove if its FmlaMacro matches removed.
    removed_macros = {
        "Tabelle1.Sortieren_Klicken",
        "Schaltzettel_Minimieren",
        "Schaltzettel_Maximieren",
        "Tabelle1.ReplaceIdentifiersInCSV",
        "Tabelle1.LeerzeilenEinfuegenOderLoeschen",
    }

    # Use a regex that captures each shape (greedy until next </v:shape>)
    def repl(m):
        block = m.group(0)
        macro_m = re.search(r"<x:FmlaMacro>\[0\]!([^<]+)</x:FmlaMacro>", block)
        if macro_m and macro_m.group(1) in removed_macros:
            return ""
        return block

    new_c = re.sub(r"<v:shape\s[^>]*>.*?</v:shape>", repl, c, flags=re.DOTALL)
    assert new_c != c, "no shapes removed"

    # Update Zurue label to clarify toggle behavior
    new_c = new_c.replace("<b>Zurue Ltg.</b>", "<b>Zurue ein/aus</b>")

    # Append 2 new shapes before </xml>
    new_shapes = """<v:shape id="_x0000_s1100" type="#_x0000_t201" style='position:absolute;
  margin-left:136.2pt;margin-top:3pt;width:130pt;height:21.6pt;z-index:5;
  mso-wrap-style:tight' o:button="t" fillcolor="buttonFace [67]" strokecolor="windowText [64]"
  o:insetmode="auto">
  <v:fill color2="buttonFace [67]" o:detectmouseclick="t"/>
  <o:lock v:ext="edit" rotation="t"/>
  <v:textbox style='mso-direction-alt:auto' o:singleclick="f">
   <div style='text-align:center'><font face="Calibri" size="200"
   color="#000000"><b>PDF Export</b></font></div>
  </v:textbox>
  <x:ClientData ObjectType="Button">
   <x:SizeWithCells/>
   <x:Anchor>
    2, 5, 0, 5, 3, 30, 0, 41</x:Anchor>
   <x:PrintObject>False</x:PrintObject>
   <x:AutoFill>False</x:AutoFill>
   <x:FmlaMacro>[0]!Tabelle1.Schaltzettel_PDFExport_Klicken</x:FmlaMacro>
   <x:TextHAlign>Center</x:TextHAlign>
   <x:TextVAlign>Center</x:TextVAlign>
  </x:ClientData>
 </v:shape><v:shape id="_x0000_s1101" type="#_x0000_t201" style='position:absolute;
  margin-left:136.2pt;margin-top:28.8pt;width:200pt;height:19.8pt;z-index:6;
  mso-wrap-style:tight' o:button="t" fillcolor="buttonFace [67]" strokecolor="windowText [64]"
  o:insetmode="auto">
  <v:fill color2="buttonFace [67]" o:detectmouseclick="t"/>
  <o:lock v:ext="edit" rotation="t"/>
  <v:textbox style='mso-direction-alt:auto' o:singleclick="f">
   <div style='text-align:center'><font face="Calibri" size="200"
   color="#000000"><b>Letzte Umschaltung r&#252;ckg&#228;ngig</b></font></div>
  </v:textbox>
  <x:ClientData ObjectType="Button">
   <x:SizeWithCells/>
   <x:Anchor>
    2, 5, 0, 48, 3, 130, 0, 81</x:Anchor>
   <x:PrintObject>False</x:PrintObject>
   <x:AutoFill>False</x:AutoFill>
   <x:FmlaMacro>[0]!Tabelle1.Schaltzettel_Undo_Klicken</x:FmlaMacro>
   <x:TextHAlign>Center</x:TextHAlign>
   <x:TextVAlign>Center</x:TextVAlign>
  </x:ClientData>
 </v:shape>"""
    new_c = new_c.replace("</xml>", new_shapes + "</xml>")

    p.write_text(new_c, encoding="utf-8")
    print("  vmlDrawing1.vml: 5 shapes removed, Zurue relabeled, 2 added")


def patch_sheet1_controls_and_rels():
    """Remove control entries and rels for removed buttons; add new ones."""
    sheet_p = SRC / "xl/worksheets/sheet1.xml"
    rels_p = SRC / "xl/worksheets/_rels/sheet1.xml.rels"

    sheet = sheet_p.read_text(encoding="utf-8")
    rels = rels_p.read_text(encoding="utf-8")

    removed_macros = {
        "Tabelle1.Sortieren_Klicken",
        "Schaltzettel_Minimieren",
        "Schaltzettel_Maximieren",
        "Tabelle1.ReplaceIdentifiersInCSV",
        "Tabelle1.LeerzeilenEinfuegenOderLoeschen",
    }
    removed_rids = set()

    def repl_ctrl(m):
        block = m.group(0)
        macro_m = re.search(r'macro="\[0\]!([^"]+)"', block)
        rid_m = re.search(r'r:id="(rId\d+)"', block)
        if macro_m and macro_m.group(1) in removed_macros:
            if rid_m:
                removed_rids.add(rid_m.group(1))
            return ""
        return block

    new_sheet = re.sub(
        r"<mc:AlternateContent[^>]*>(?:(?!</mc:AlternateContent>).)*?<control [^>]*>.*?</mc:AlternateContent>",
        repl_ctrl,
        sheet,
        flags=re.DOTALL,
    )
    assert new_sheet != sheet, "no controls removed"

    # Remove rels for removed rIds. Note: Type attribute contains URLs with /,
    # so [^/]* would stop early. Use a non-greedy match for any attribute chars
    # ending at the self-closing />.
    for rid in removed_rids:
        rels = re.sub(rf'<Relationship Id="{rid}" [^>]*?/>', "", rels)

    # Find max existing rId number
    rid_nums = [int(m) for m in re.findall(r'Id="rId(\d+)"', rels)]
    next_rid = max(rid_nums) + 1 if rid_nums else 1

    # Allocate 2 new rIds and 2 new ctrlProp file numbers
    rid_pdf = f"rId{next_rid}"
    rid_undo = f"rId{next_rid+1}"
    # Re-use ctrlProp slots 5 and 6 (Maximieren and Search&Replace removed) - or new ones
    # Be safe: use 9 and 10
    pdf_ctrl_n = 9
    undo_ctrl_n = 10

    # Add new rels
    new_rels_entries = (
        f'<Relationship Id="{rid_pdf}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/ctrlProp" Target="../ctrlProps/ctrlProp{pdf_ctrl_n}.xml"/>'
        f'<Relationship Id="{rid_undo}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/ctrlProp" Target="../ctrlProps/ctrlProp{undo_ctrl_n}.xml"/>'
    )
    rels = rels.replace("</Relationships>", new_rels_entries + "</Relationships>")

    # Add new controls before </controls>
    new_controls = (
        f'<mc:AlternateContent xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006">'
        f'<mc:Choice Requires="x14">'
        f'<control shapeId="1100" r:id="{rid_pdf}" name="Button PDF Export">'
        f'<controlPr defaultSize="0" print="0" autoFill="0" autoPict="0" macro="[0]!Tabelle1.Schaltzettel_PDFExport_Klicken">'
        f'<anchor moveWithCells="1"><from><xdr:col>2</xdr:col><xdr:colOff>38100</xdr:colOff><xdr:row>0</xdr:row><xdr:rowOff>38100</xdr:rowOff></from>'
        f'<to><xdr:col>3</xdr:col><xdr:colOff>381000</xdr:colOff><xdr:row>0</xdr:row><xdr:rowOff>312420</xdr:rowOff></to></anchor>'
        f'</controlPr></control></mc:Choice></mc:AlternateContent>'
        f'<mc:AlternateContent xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006">'
        f'<mc:Choice Requires="x14">'
        f'<control shapeId="1101" r:id="{rid_undo}" name="Button Undo Umschaltung">'
        f'<controlPr defaultSize="0" print="0" autoFill="0" autoPict="0" macro="[0]!Tabelle1.Schaltzettel_Undo_Klicken">'
        f'<anchor moveWithCells="1"><from><xdr:col>2</xdr:col><xdr:colOff>38100</xdr:colOff><xdr:row>0</xdr:row><xdr:rowOff>365760</xdr:rowOff></from>'
        f'<to><xdr:col>3</xdr:col><xdr:colOff>1651000</xdr:colOff><xdr:row>0</xdr:row><xdr:rowOff>617220</xdr:rowOff></to></anchor>'
        f'</controlPr></control></mc:Choice></mc:AlternateContent>'
    )
    new_sheet = new_sheet.replace("</controls>", new_controls + "</controls>")

    sheet_p.write_text(new_sheet, encoding="utf-8")
    rels_p.write_text(rels, encoding="utf-8")
    print(f"  sheet1.xml: removed rIds {sorted(removed_rids)}, added {rid_pdf}+{rid_undo}")
    return pdf_ctrl_n, undo_ctrl_n


def patch_ctrlprops(pdf_n, undo_n):
    """Remove ctrlProps for removed buttons, add new ones."""
    ctrl_dir = SRC / "xl/ctrlProps"
    for n in (3, 5, 6, 7, 8):  # Sortierung, Min, Max, S&R, Leerzeile
        f = ctrl_dir / f"ctrlProp{n}.xml"
        if f.exists():
            f.unlink()
            print(f"    removed ctrlProp{n}.xml")
    template = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<formControlPr xmlns="http://schemas.microsoft.com/office/spreadsheetml/2009/9/main" objectType="Button" lockText="1"/>'
    )
    (ctrl_dir / f"ctrlProp{pdf_n}.xml").write_text(template, encoding="utf-8")
    (ctrl_dir / f"ctrlProp{undo_n}.xml").write_text(template, encoding="utf-8")
    print(f"  ctrlProps: added ctrlProp{pdf_n}.xml + ctrlProp{undo_n}.xml")


def patch_content_types(pdf_n, undo_n):
    """Add overrides for new ctrlProp files in [Content_Types].xml; remove entries for deleted ones."""
    p = SRC / "[Content_Types].xml"
    c = p.read_text(encoding="utf-8")
    # Remove overrides for deleted ctrlProps
    for n in (3, 5, 6, 7, 8):
        c = re.sub(rf'<Override PartName="/xl/ctrlProps/ctrlProp{n}\.xml"[^/]*/>', "", c)
    # Add overrides for new ones (if not already present)
    insert = (
        f'<Override PartName="/xl/ctrlProps/ctrlProp{pdf_n}.xml" ContentType="application/vnd.ms-excel.controlproperties+xml"/>'
        f'<Override PartName="/xl/ctrlProps/ctrlProp{undo_n}.xml" ContentType="application/vnd.ms-excel.controlproperties+xml"/>'
    )
    if f'ctrlProp{pdf_n}.xml' not in c:
        c = c.replace("</Types>", insert + "</Types>")
    p.write_text(c, encoding="utf-8")
    print("  [Content_Types].xml updated")


def patch_changelog_and_anleitung():
    """Add v2.7 changelog entry to sharedStrings."""
    p = SRC / "xl/sharedStrings.xml"
    c = p.read_text(encoding="utf-8")
    new_entry = "<si><t>v2.7 Optimierung: Search&amp;Replace, Min/Max, Sortier-Button und Leerzeilen-Funktion entfernt. Umschaltung um Anzahl-Stifte-Limit erweitert. Neue Buttons: PDF-Export, Undo (letzte Umschaltung). Zurue-Ltg ist jetzt Toggle (ein/aus).</t></si>"
    # Insert before closing </sst>; bump count and uniqueCount accordingly
    c2 = c.replace("</sst>", new_entry + "</sst>")
    # bump count + uniqueCount
    c2 = re.sub(r'count="(\d+)" uniqueCount="(\d+)"',
                lambda m: f'count="{int(m.group(1))+1}" uniqueCount="{int(m.group(2))+1}"',
                c2, count=1)
    p.write_text(c2, encoding="utf-8")
    print("  Changelog v2.7 added to sharedStrings.xml")


def repackage():
    """Zip src/ back into the xlsm."""
    if OUT.exists():
        OUT.unlink()
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, _, files in os.walk(SRC):
            for fn in files:
                fp = Path(root) / fn
                arcname = fp.relative_to(SRC).as_posix()
                zf.write(fp, arcname)
    print(f"  repackaged -> {OUT} ({OUT.stat().st_size/1024:.1f} KB)")


def main():
    print("Building optimized xlsm v2.7")
    reset_src()
    strip_workbook_protection()
    patch_vml()
    pdf_n, undo_n = patch_sheet1_controls_and_rels()
    patch_ctrlprops(pdf_n, undo_n)
    patch_content_types(pdf_n, undo_n)
    patch_changelog_and_anleitung()
    repackage()
    print("Done.")


if __name__ == "__main__":
    main()
