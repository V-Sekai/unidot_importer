# unidot Importer

A Unity compatibility layer and unitypackage importer for Godot.

## Features

- Direct importers for Unity filetypes (such as .unity). This will be removed and changed to a .tscn translator at import time.
- Implementation of an asset database for unity assets by GUID
- Unitypackage importer and translation shim.
- The Godot FBX importer is not yet feature complete. We rely on automatic FBX to glTF translation during unitypackage import using FBX2glTF.

## Installation notes:

1. This project should be imported at addons/unidot in your project, often as a git submodule.

2. Most unity assets use .fbx files. This requires additional setup:

  Godot's .fbx implementation is not feature complete, and can corrupt normals or fail in some common cases, such as FBX files exported by Blender.

  To install, you must download FBX2glTF from https://github.com/revolufire/FBX2glTF/releases/ then rename to FBX2glTF.exe and move it into this addon directory.

3. Finally, enable the Unidot-Importer plugin in Project Settings -> Plugins tab -> Unidot

4. Access the importer through Project -> Tools -> Import Unity Package...
