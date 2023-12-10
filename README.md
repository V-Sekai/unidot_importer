# Unidot Importer

Unify your Godot asset interop with **Unidot**, a **Uni**versal Go**dot** Engine source asset translator and interoperability pipeline for Godot 4.

At its heart, Unidot Importer can convert `.unitypackage` assets and asset folders into Godot 4.x compatible formats.

It takes original **source assets** and *translates* them into Godot native equivalents.
For example, `.unity` and `.prefab` become `.tscn` and `.prefab.tscn`.

FBX Files are currently ported to glTF but this may be made more flexible in the future.

Raw mesh, anim, material assets and more are converted directly to godot `.tres/.res` equivalents.

Due to being a translator, Unidot may safely be removed from the project when completed. (other than `runtime/anim_tree.gd`)

## Made for Godot Engine 4

We rely on automatic FBX to glTF translation during `.unitypackage` import using FBX2glTF. [please download the FBX2glTF exe](https://github.com/godotengine/FBX2glTF/releases) and configure FBX Import in Godot Editor Settings before using Unidot.

Please use a version of Godot 4.0 or later with FBX2glTF configured in Editor Settings to run this addon.

## Features

- `.unitypackage` importer and translation shim.
- Translates native filetypes (such as .unity or .mat) to Godot native scene or resource types.
- Animation and animation tree porting, including humanoid .anim format.
- Support for humanoid armatures, including from prefabs, unpacked prefabs and model import.
- Translates prefabs and inherited prefabs to native Godot scenes and inherited scenes.
- Supports both binary and text YAML encoding
- Implementation of an asset database by GUID

Note that scripts and shaders will need to be ported by hand. However, it will be possible to map scripts/shaders to Godot equivalents after porting.

Canvas / UI is not implemented.

## Supported asset types:

* Mesh/MeshFilter/MeshRenderer/SkinnedMeshRenderer
* Material (standard shader only)
* Avatar
* AnimationClip
* AnimatorController (relies on small runtime helper script `unidot_importer/runtime/anim_tree.gd`)
* AnimatorState/AnimatorStateMachine/AnimatorTransitionBase/BlendTree
* PrefabInstance (prefabs)
* GameObject/Transform/Collider/SkinnedMeshRenderer/MeshFilter/Animator/Light/Camera etc. (scenes)
* Texture2D/CubeMap/Texture2DArray etc.
* AssetImporter
* AudioClip/AudioSource
* Collider/Rigidbody
* Terrain (limited support for detail meshes as MultiMeshInstance)
* LightingSettings/PostProcessLayer

## Unsupported

* Shader: a system may someday be added to create mappings of equivalent Godot Engine shaders, but porting must be done by hand.
* MonoBehaviour (C# Script porting)
* AvatarMask (waiting for better Godot engine support)
* Anything not listed above

## Installation notes:

1. This project should be imported at `addons/unidot` in the project, often as a git submodule.

2. Most assets from other engines use .fbx files. To support FBX requires additional setup before import:

  To install FBX support, one must download FBX2glTF from https://github.com/godotengine/FBX2glTF/releases and set it in the FBX2glTF.exe path in the Import category of **Editor Settings** (not Project Settings)

3. To add TIFF / .tif and PSD / .psd support, install ImageMagick or GraphicsMagick into your system path or copy convert.exe into this addon directory.

4. Finally, enable the Unidot Importer plugin in `Project Settings -> Plugins tab -> Unidot`

5. Access the importer through `Project -> Tools -> Import .unitypackage...` and select a package or an asset folder

## A final note:

This tool is designed to assist with importing or translating source assets made for use in the editor. It makes an assumption that (other than animator controllers) most yaml files contain only one object).

Unidot solely translates existing usable source assets into equivalent Godot source assets. There are no plans to add functionality for decompiling asset bundles or ripping game content. That is not the goal of this project.
