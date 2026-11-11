"""Enable document access in a development IPA, preserving every other plist value."""
import argparse
import pathlib
import plistlib
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source_ipa", type=pathlib.Path)
parser.add_argument("output_plist", type=pathlib.Path)
args = parser.parse_args()
if args.output_plist.exists():
    parser.error("Output already exists")
with zipfile.ZipFile(args.source_ipa) as archive:
    candidates = [name for name in archive.namelist()
                  if name.startswith("Payload/") and name.count("/") == 2
                  and name.endswith(".app/Info.plist")]
    if len(candidates) != 1:
        parser.error("Expected exactly one application Info.plist")
    original = plistlib.loads(archive.read(candidates[0]))
if original.get("CFBundleExecutable") != "Standoff2":
    parser.error("Unexpected application executable")
modified = dict(original)
modified["UIFileSharingEnabled"] = True
modified["LSSupportsOpeningDocumentsInPlace"] = True
data = plistlib.dumps(modified, fmt=plistlib.FMT_XML, sort_keys=False)
if plistlib.loads(data) != modified:
    raise ValueError("Plist round trip failed")
args.output_plist.parent.mkdir(parents=True, exist_ok=True)
with args.output_plist.open("xb") as stream:
    stream.write(data)
print("Prepared development Info.plist; only document access flags changed.")
