from pathlib import Path

from run_grader import copy_candidate_project, inject_verifier


DEBUG_SCENE_RELATIVE_PATH = Path("__verifier__") / "debug_arena.tscn"


def export_debug_project(source_project: Path, output_project: Path, verifier_root: Path) -> Path:
    source_project = Path(source_project)
    output_project = Path(output_project)
    verifier_root = Path(verifier_root)

    copy_candidate_project(source_project, output_project)
    inject_verifier(verifier_root, output_project)

    debug_scene = output_project / DEBUG_SCENE_RELATIVE_PATH
    if not debug_scene.exists():
        raise FileNotFoundError(f"Verifier debug scene was not injected: {debug_scene}")
    return debug_scene
