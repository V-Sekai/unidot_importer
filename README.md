# unidot Importer

A Unity compatibility layer and unitypackage importer for Godot.

## Features

- Translates unity filetypes (such as .unity, .mat, etc) to Godot native scene or resource types.
- Implementation of an asset database for unity assets by GUID
- Unitypackage importer and translation shim.
- The Godot FBX importer is not yet feature complete. We rely on automatic FBX to glTF translation during unitypackage import using FBX2glTF.

Note that scripts and shaders will need to be ported by hand. After porting, it will be possible to make a mapping from the unity scripts/shaders to Godot equivalents.

Many import settings that exist in Unity are not implemented in Godot, for example recompute tangents or specific texture compression settings.

Canvas / UI is not implemented.

## Unsupported

- Shader porting: a system will be added to create mappings of equivalent Godot shaders, but porting must be done by hand.
- C# Script porting
- 

## Installation notes:

1. This project should be imported at addons/unidot in your project, often as a git submodule.

2. Most unity assets use .fbx files. This requires additional setup:

  Godot's .fbx implementation is not feature complete, and can corrupt normals or fail in some common cases, such as FBX files exported by Blender.

  To install, you must download FBX2glTF from https://github.com/revolufire/FBX2glTF/releases/ then rename to FBX2glTF.exe and move it into this addon directory.

3. Finally, enable the Unidot-Importer plugin in Project Settings -> Plugins tab -> Unidot

4. Access the importer through Project -> Tools -> Import Unity Package...

## A final note:

This tool is designed to assist with importing or translating source assets made for Unity Engine, and assumes text serialization (such as within a .unitypackage archive) as well as typical asset conventions (for example, an assumption that most files contain only one asset).

Unidot solely translates existing usable source assets into equivalent Godot source assets. There are no plans to add functionality for decompiling binary assets or ripping unity content. That is not a goal of this project.
