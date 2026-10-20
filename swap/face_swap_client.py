import os
import json
import base64
import hashlib
import mimetypes
import argparse
import glob
import uuid
import tempfile
from io import BytesIO


# Try to import required third-party libraries
try:
    import requests
except ImportError:
    print("Error: The 'requests' library is not installed. Please run: pip install requests")
    exit(1)

try:
    from PIL import Image
except ImportError:
    print("Error: The 'Pillow' library is not installed. Please run: pip install Pillow")
    exit(1)

try:
    import pillow_heif
    pillow_heif.register_heif_opener()
except ImportError:
    print("Error: The 'pillow-heif' library is not installed. Please run: pip install pillow-heif")
    exit(1)

try:
    from gradio_client import Client, handle_file
except ImportError:
    print("Error: The 'gradio_client' library is not installed. Please run: pip install gradio_client")
    exit(1)


def load_config(config_path="appsettings.json"):
    """Loads the settings from the JSON configuration file."""
    if not os.path.exists(config_path):
        print(f"Warning: Configuration file '{config_path}' not found. Using defaults.")
        return {}
    
    with open(config_path, "r", encoding="utf-8") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as e:
            print(f"Error: Failed to parse configuration file '{config_path}': {e}")
            exit(1)


def get_base64_image(image_path, include_header=False):
    """Reads a local image and converts it to a base64 encoded string."""
    if not os.path.exists(image_path):
        print(f"Error: Local image file '{image_path}' not found.")
        exit(1)
        
    with open(image_path, "rb") as image_file:
        encoded_string = base64.b64encode(image_file.read()).decode("utf-8")
        
    if include_header:
        mime_type, _ = mimetypes.guess_type(image_path)
        if not mime_type:
            mime_type = "image/jpeg"
        return f"data:{mime_type};base64,{encoded_string}"
    
    return encoded_string


def get_nested_value(data, path):
    """Retrieves a nested value from a dictionary/list structure using a dot-separated path."""
    if not path:
        return data
    parts = path.split('.')
    current = data
    for part in parts:
        if isinstance(current, dict):
            current = current.get(part)
        elif isinstance(current, list):
            try:
                idx = int(part)
                current = current[idx]
            except (ValueError, IndexError):
                return None
        else:
            return None
    return current


def calculate_hash(data_bytes, algorithm="sha256"):
    """Calculates the hash of data bytes using the specified algorithm."""
    algo = algorithm.lower()
    if algo == "sha256":
        return hashlib.sha256(data_bytes).hexdigest()
    elif algo == "md5":
        return hashlib.md5(data_bytes).hexdigest()
    elif algo == "sha1":
        return hashlib.sha1(data_bytes).hexdigest()
    else:
        return hashlib.sha256(data_bytes).hexdigest()


def resolve_images(inputs):
    """Resolves inputs (files, directories, list of files) into a sorted list of image file paths."""
    resolved_paths = []
    valid_exts = {".jpg", ".jpeg", ".png", ".webp", ".heic", ".heif"}
    
    if not inputs:
        return resolved_paths
        
    # Standardize input to list
    if isinstance(inputs, str):
        inputs = [inputs]
        
    for item in inputs:
        if os.path.isdir(item):
            # Read and sort all images in the directory
            dir_files = []
            for entry in os.scandir(item):
                if entry.is_file() and os.path.splitext(entry.name.lower())[1] in valid_exts:
                    dir_files.append(entry.path)
            dir_files.sort()
            resolved_paths.extend(dir_files)
        elif os.path.isfile(item):
            resolved_paths.append(item)
        else:
            # Support glob patterns (e.g. target_*.heic)
            glob_files = glob.glob(item)
            if glob_files:
                glob_files = [f for f in glob_files if os.path.isfile(f)]
                glob_files.sort()
                resolved_paths.extend(glob_files)
            else:
                print(f"Warning: Path '{item}' does not exist or matches no files.")
                
    # Deduplicate while preserving order
    seen = set()
    return [p for p in resolved_paths if not (p in seen or seen.add(p))]


GRADIO_SETTINGS_MAPPING = {
    "processors": ("/update_processors", list),
    "age_modifier_model": ("/update_age_modifier_model", str),
    "age_modifier_direction": ("/update_age_modifier_direction", float),
    "background_remover_model": ("/update_background_remover_model", str),
    "deep_swapper_model": ("/update_deep_swapper_model", str),
    "deep_swapper_morph": ("/update_deep_swapper_morph", float),
    "expression_restorer_model": ("/update_expression_restorer_model", str),
    "expression_restorer_factor": ("/update_expression_restorer_factor", float),
    "expression_restorer_areas": ("/update_expression_restorer_areas", list),
    "face_debugger_items": ("/update_face_debugger_items", list),
    "face_editor_model": ("/update_face_editor_model", str),
    "face_editor_eyebrow_direction": ("/update_face_editor_eyebrow_direction", float),
    "face_editor_eye_gaze_horizontal": ("/update_face_editor_eye_gaze_horizontal", float),
    "face_editor_eye_gaze_vertical": ("/update_face_editor_eye_gaze_vertical", float),
    "face_editor_eye_open_ratio": ("/update_face_editor_eye_open_ratio", float),
    "face_editor_lip_open_ratio": ("/update_face_editor_lip_open_ratio", float),
    "face_editor_mouth_grim": ("/update_face_editor_mouth_grim", float),
    "face_editor_mouth_pout": ("/update_face_editor_mouth_pout", float),
    "face_editor_mouth_purse": ("/update_face_editor_mouth_purse", float),
    "face_editor_mouth_smile": ("/update_face_editor_mouth_smile", float),
    "face_editor_mouth_position_horizontal": ("/update_face_editor_mouth_position_horizontal", float),
    "face_editor_mouth_position_vertical": ("/update_face_editor_mouth_position_vertical", float),
    "face_editor_head_pitch": ("/update_face_editor_head_pitch", float),
    "face_editor_head_yaw": ("/update_face_editor_head_yaw", float),
    "face_editor_head_roll": ("/update_face_editor_head_roll", float),
    "face_enhancer_model": ("/update_face_enhancer_model", str),
    "face_enhancer_blend": ("/update_face_enhancer_blend", float),
    "face_enhancer_weight": ("/update_face_enhancer_weight", float),
    "face_swapper_model": ("/update_face_swapper_model", str),
    "face_swapper_pixel_boost": ("/update_face_swapper_pixel_boost", str),
    "face_swapper_weight": ("/update_face_swapper_weight", float),
    "frame_colorizer_model": ("/update_frame_colorizer_model", str),
    "frame_colorizer_size": ("/update_frame_colorizer_size", str),
    "frame_colorizer_blend": ("/update_frame_colorizer_blend", float),
    "frame_enhancer_model": ("/update_frame_enhancer_model", str),
    "frame_enhancer_blend": ("/update_frame_enhancer_blend", float),
    "lip_syncer_model": ("/update_lip_syncer_model", str),
    "lip_syncer_weight": ("/update_lip_syncer_weight", float),
    "execution_providers": ("/update_execution_providers", list),
    "execution_thread_count": ("/update_execution_thread_count", float),
    "download_providers": ("/update_download_providers", list),
    "video_memory_strategy": ("/update_video_memory_strategy", str),
    "system_memory_limit": ("/update_system_memory_limit", float),
    "temp_frame_format": ("/update_temp_frame_format", str),
    "output_image_quality": ("/update_output_image_quality", float),
    "output_image_scale": ("/update_output_image_scale", float),
    "output_audio_encoder": ("/update_output_audio_encoder", str),
    "output_audio_quality": ("/update_output_audio_quality", float),
    "output_audio_volume": ("/update_output_audio_volume", float),
    "output_video_encoder": ("/update_output_video_encoder", str),
    "output_video_preset": ("/update_output_video_preset", str),
    "output_video_quality": ("/update_output_video_quality", float),
    "output_video_scale": ("/update_output_video_scale", float),
    "output_video_fps": ("/update_output_video_fps", float),
    "face_selector_mode": ("/update_face_selector_mode", str),
    "face_selector_order": ("/update_face_selector_order", str),
    "face_selector_gender": ("/update_face_selector_gender", str),
    "face_selector_race": ("/update_face_selector_race", str),
    "reference_face_distance": ("/update_reference_face_distance", float),
    "face_mask_types": ("/update_face_mask_types", list),
    "face_mask_regions": ("/update_face_mask_regions", list),
    "face_mask_blur": ("/update_face_mask_blur", float),
    "face_mask_padding": ("/update_face_mask_padding", list),
    "face_detector_model": ("/update_face_detector_model", str),
    "face_detector_size": ("/update_face_detector_size", str),
    "face_detector_margin": ("/update_face_detector_margin", float),
    "face_detector_angles": ("/update_face_detector_angles", list),
    "face_detector_score": ("/update_face_detector_score", float),
    "common_options": ("/update_3", list),
    "keep_temp": ("/update_3", bool),
}


def main():
    # Setup argparse for CLI overrides
    parser = argparse.ArgumentParser(description="FaceFusion API Client - Batch Face Swapper")
    parser.add_index = False # prevent default index behaviors
    parser.add_argument("source_image", nargs="?", help="Filename of the source face image inside source_image_path, or direct file path")
    parser.add_argument("-s", "--source", help="Path to the source face image (Overrides appsettings.json)")
    parser.add_argument("-t", "--targets", nargs="+", help="Path(s) to target image(s), directory, or glob pattern (Overrides appsettings.json)")
    parser.add_argument("-o", "--output-dir", help="Output directory path (Overrides appsettings.json)")
    parser.add_argument("-c", "--config", default="appsettings.json", help="Path to the config file (Default: appsettings.json)")
    parser.add_argument("-w", "--swap", type=str.upper, choices=["Y", "N"], default="Y", help="Swap face option: Y to swap, N to not swap (Default: Y)")
    parser.add_argument("--face-enhancer-blend", type=float, help="Face enhancer blend value (0-100) (Overrides appsettings.json, default: 60)")
    parser.add_argument("--face-selector-order", choices=["left-right", "right-left", "top-bottom", "bottom-top", "small-large", "large-small", "best-worst", "worst-best"], help="Face selector order (left-right, right-left, top-bottom, bottom-top, small-large, large-small, best-worst, worst-best) (Overrides appsettings.json)")
    parser.add_argument("--face-selector-gender", choices=["none", "female", "male"], help="Face selector gender (none, female, male) (Overrides appsettings.json)")
    parser.add_argument("--face-selector-race", choices=["none", "white", "black", "latino", "asian", "indian", "arabic"], help="Face selector race (Overrides appsettings.json)")
    parser.add_argument("--reference-face-distance", type=float, help="Reference face distance (0.0 to 1.0) (Overrides appsettings.json)")
    parser.add_argument("--hash-by-inputs", type=str.upper, choices=["Y", "N"], default=None, help="Hash output filename by inputs instead of output content: Y to enable, N to disable")
    parser.add_argument("--api-url", help="FaceFusion API endpoint URL (Overrides appsettings.json)")
    
    args = parser.parse_args()
    
    # Load configuration
    config = load_config(args.config)
    
    should_swap = args.swap == "Y"
    
    # Resolve source image (reference face)
    source_path = None
    if should_swap:
        source_config = config.get("source_image_path", "source")
        
        if args.source_image:
            # Check if the positional argument is a direct file path that exists
            if os.path.exists(args.source_image) and os.path.isfile(args.source_image):
                source_path = args.source_image
            else:
                # Try combining with source_config directory
                combined_path = os.path.join(source_config, args.source_image)
                if os.path.exists(combined_path) and os.path.isfile(combined_path):
                    source_path = combined_path
                else:
                    print(f"Error: Source image '{args.source_image}' not found directly or in '{source_config}'.")
                    exit(1)
        else:
            # Fallback to -s option or configuration directly
            source_path = args.source if args.source else source_config
            if not source_path or not os.path.exists(source_path):
                print(f"Error: Source image path '{source_path}' does not exist.")
                exit(1)
                
            if os.path.isdir(source_path):
                # Resolve all images in the source directory and pick the first one as the default source face
                images = resolve_images(source_path)
                if not images:
                    print(f"Error: No valid images found in source directory '{source_path}'.")
                    exit(1)
                source_path = images[0]
            
    # Resolve target images (batch)
    target_config = config.get("target_image_path", "target")
    target_inputs = args.targets if args.targets else target_config
    
    resolved_targets = resolve_images(target_inputs)
    if not resolved_targets:
        print("Error: No valid target images resolved. Please specify target images.")
        exit(1)
        
    # Read output settings
    output_dir = args.output_dir if args.output_dir else config.get("output_dir", "output")
    hash_algo = config.get("hash_algorithm", "sha256")
    include_b64_header = config.get("include_base64_header", False)
    img_quality = config.get("quality", 100)
    hash_by_inputs = config.get("hash_by_inputs", False)
    if args.hash_by_inputs is not None:
        hash_by_inputs = args.hash_by_inputs == "Y"

    # Calculate source image hash if needed
    source_hash = ""
    if should_swap and source_path and os.path.exists(source_path):
        try:
            with open(source_path, "rb") as sf:
                source_hash = calculate_hash(sf.read(), algorithm=hash_algo)
        except Exception as e:
            print(f"Warning: Failed to calculate source image hash: {e}")
    
    # API settings
    api_url = args.api_url if args.api_url else config.get("api_url", "http://127.0.0.1:7860/api/predict")
    
    # Extract base Gradio URL for gradio_client
    gradio_url = api_url
    for suffix in ["/api/predict/", "/api/predict", "/api/", "/api"]:
        if gradio_url.endswith(suffix):
            gradio_url = gradio_url[:-len(suffix)]
            break
            
    print("=== FaceFusion API Client (Batch Process) ===")
    if should_swap:
        print(f"Source Face Image (Reference): {source_path}")
    else:
        print("Face swapping is DISABLED (--swap N)")
    print(f"Resolved Targets ({len(resolved_targets)} files):")
    for idx, path in enumerate(resolved_targets, 1):
        print(f"  [{idx}] {path}")
    print("---------------------------------------------")
    
    # Initialize Gradio Client and apply settings if swapping faces
    client = None
    settings_hash = ""
    if should_swap:
        print(f"Connecting to Gradio server: {gradio_url} ...")
        try:
            client = Client(gradio_url)
        except Exception as e:
            print(f"Error: Failed to connect to Gradio server: {e}")
            print(f"__FACESWAP_ERROR_JSON__: {json.dumps({'status': 'error', 'message': f'Failed to connect to Gradio server ({gradio_url}): {e}'})}")
            exit(1)
            
        # Apply FaceFusion custom settings from config
        ff_settings = config.get("facefusion_settings", {})
        if ff_settings is None:
            ff_settings = {}
            
        # Override face_enhancer_blend from CLI or configuration (default to 60.0 if not specified in either)
        blend_val = args.face_enhancer_blend
        if blend_val is None:
            blend_val = ff_settings.get("face_enhancer_blend", 60.0)
        ff_settings["face_enhancer_blend"] = blend_val

        # Override face_selector_order from CLI or configuration (default to "best-worst" if not specified in either)
        order_val = args.face_selector_order
        if order_val is None:
            order_val = ff_settings.get("face_selector_order", "best-worst")
        ff_settings["face_selector_order"] = order_val

        # Override face_selector_gender from CLI or configuration (default to "none" if not specified in either)
        gender_val = args.face_selector_gender
        if gender_val is None:
            gender_val = ff_settings.get("face_selector_gender", "none")
        ff_settings["face_selector_gender"] = gender_val

        # Override face_selector_race from CLI or configuration (default to "none" if not specified in either)
        race_val = args.face_selector_race
        if race_val is None:
            race_val = ff_settings.get("face_selector_race", "none")
        ff_settings["face_selector_race"] = race_val

        # Override reference_face_distance from CLI or configuration (default to 0.3 if not specified in either)
        distance_val = args.reference_face_distance
        if distance_val is None:
            distance_val = ff_settings.get("reference_face_distance", 0.3)
        ff_settings["reference_face_distance"] = distance_val

        # Calculate settings hash
        if ff_settings:
            try:
                settings_str = json.dumps(ff_settings, sort_keys=True)
                settings_hash = calculate_hash(settings_str.encode("utf-8"), algorithm=hash_algo)
            except Exception as e:
                print(f"Warning: Failed to serialize settings: {e}")

        if ff_settings:
            print("\nApplying FaceFusion settings from configuration...")
            for setting_key, val in ff_settings.items():
                if setting_key in GRADIO_SETTINGS_MAPPING:
                    api_name, cast_type = GRADIO_SETTINGS_MAPPING[setting_key]
                    try:
                        # Convert types if needed
                        if api_name == "/update_face_mask_padding":
                            if isinstance(val, list) and len(val) == 4:
                                converted_val = [float(x) for x in val]
                            else:
                                print(f"  Warning: face_mask_padding must be a list of 4 floats [top, right, bottom, left]")
                                continue
                            print(f"  Setting {setting_key} -> {converted_val} via {api_name} ...")
                            client.predict(*converted_val, api_name=api_name)
                            continue
                        elif api_name == "/update_face_detector_angles":
                            converted_val = [int(x) for x in val] if isinstance(val, list) else [int(val)]
                        elif api_name == "/update_3" or setting_key == "keep_temp":
                            if isinstance(val, bool):
                                converted_val = ["keep-temp"] if val else []
                            elif isinstance(val, list):
                                converted_val = val
                            else:
                                converted_val = [str(val)]
                            # Force api_name to /update_3 in case key was keep_temp
                            api_name = "/update_3"
                        elif cast_type == float and not isinstance(val, (int, float)):
                            converted_val = float(val)
                        elif cast_type == list and not isinstance(val, list):
                            converted_val = [val]
                        elif cast_type == str and not isinstance(val, str):
                            converted_val = str(val)
                        else:
                            converted_val = val
                            
                        print(f"  Setting {setting_key} -> {converted_val} via {api_name} ...")
                        client.predict(converted_val, api_name=api_name)
                    except Exception as e:
                        print(f"  Warning: Failed to apply setting '{setting_key}': {e}")
                else:
                    print(f"  Warning: Unknown setting key '{setting_key}' in facefusion_settings.")
            
        # Upload source image (only once)
        print(f"Uploading source face image: {source_path} ...")
        try:
            client.predict([handle_file(source_path)], api_name="/update")
        except Exception as e:
            print(f"Error: Failed to upload source face image to Gradio server: {e}")
            exit(1)
        
    # Ensure output directory exists
    if not os.path.exists(output_dir):
        os.makedirs(output_dir, exist_ok=True)
        print(f"Created output directory: {output_dir}")
        
    # Process targets in order
    for idx, target_path in enumerate(resolved_targets, 1):
        print(f"\n[{idx}/{len(resolved_targets)}] Processing target image: {target_path}")
        
        # Calculate target image hash if needed
        target_hash = ""
        if hash_by_inputs:
            try:
                with open(target_path, "rb") as tf:
                    target_hash = calculate_hash(tf.read(), algorithm=hash_algo)
            except Exception as e:
                print(f"  Warning: Failed to calculate target image hash: {e}")
        
        temp_target_path = None
        upload_target_path = target_path

        # If target image is HEIC/HEIF, convert to JPG before sending to API
        ext = os.path.splitext(target_path)[1].lower()
        if ext in [".heic", ".heif"]:
            try:
                temp_file = tempfile.NamedTemporaryFile(suffix=".jpg", delete=False)
                temp_target_path = temp_file.name
                temp_file.close()

                with Image.open(target_path) as img:
                    if img.mode != "RGB":
                        img = img.convert("RGB")
                    img.save(temp_target_path, format="JPEG", quality=100, subsampling=0)
                upload_target_path = temp_target_path
                print(f"  -> Converted HEIC target to temporary JPG: {temp_target_path}")
            except Exception as e:
                print(f"  -> Warning: Failed to convert HEIC target to JPG ({e}), falling back to original file.")
                upload_target_path = target_path

        try:
            if should_swap:
                # Upload target image
                try:
                    client.predict(handle_file(upload_target_path), api_name="/update_1")
                except Exception as e:
                    print(f"  -> Skip: Failed to upload target image: {e}")
                    print(f"__FACESWAP_ERROR_JSON__: {json.dumps({'status': 'error', 'message': f'Failed to upload target image: {e}', 'target_path': target_path})}")
                    continue
                    
                # Run face swap
                try:
                    res = client.predict(api_name="/run")
                except Exception as e:
                    print(f"  -> Error running face swap: {e}")
                    print(f"__FACESWAP_ERROR_JSON__: {json.dumps({'status': 'error', 'message': f'Face swap execution error: {e}', 'target_path': target_path})}")
                    continue
                    
                # Extract response image path
                try:
                    image_data = res[0]
                    if not isinstance(image_data, dict) or not image_data.get('value'):
                        print(f"  -> Error: Unexpected result format from server: {res}")
                        continue
                    output_image_path = image_data['value']
                    
                    with open(output_image_path, "rb") as f:
                        image_bytes = f.read()
                except Exception as e:
                    print(f"  -> Error reading response image data: {e}")
                    continue
            else:
                # No face swapping: use target image directly
                output_image_path = target_path
                try:
                    with open(output_image_path, "rb") as f:
                        image_bytes = f.read()
                except Exception as e:
                    print(f"  -> Error reading target image: {e}")
                    continue
                
            # Convert to 100% Quality HEIC
            try:
                img = Image.open(BytesIO(image_bytes))
                if img.mode != "RGB":
                    img = img.convert("RGB")
                    
                output_buffer = BytesIO()
                img.save(output_buffer, format="HEIF", quality=img_quality)
                heic_bytes = output_buffer.getvalue()
                
            except Exception as e:
                print(f"  -> Error converting image to HEIC: {e}")
                continue
                
            # Calculate Hash and Save
            # To avoid duplicate hashes, we include the source path, target path, and a random UUID
            unique_suffix = uuid.uuid4().hex
            if hash_by_inputs:
                combined_input = f"{source_path}:{source_hash}:{target_path}:{target_hash}:{settings_hash}:{unique_suffix}".encode("utf-8")
                filename_hash = calculate_hash(combined_input, algorithm=hash_algo)
            else:
                combined_input = heic_bytes + f":{target_path}:{unique_suffix}".encode("utf-8")
                filename_hash = calculate_hash(combined_input, algorithm=hash_algo)
            
            # Avoid file collision / duplicate filenames by appending a counter
            filename = f"{filename_hash}.heic"
            output_path = os.path.join(output_dir, filename)
            counter = 1
            while os.path.exists(output_path):
                filename = f"{filename_hash}_{counter}.heic"
                output_path = os.path.join(output_dir, filename)
                counter += 1
                
            try:
                with open(output_path, "wb") as out_file:
                    out_file.write(heic_bytes)
                print(f"  -> Success! Saved as {filename}")
                print(f"__FACESWAP_RESULT_JSON__: {json.dumps({'status': 'success', 'output_path': os.path.abspath(output_path), 'filename': filename, 'target_path': os.path.abspath(target_path), 'source_path': os.path.abspath(source_path) if source_path else ''})}")
                
                # Update faceswap_manifest.json in output_dir
                try:
                    manifest_path = os.path.join(output_dir, "faceswap_manifest.json")
                    manifest_data = {"items": []}
                    if os.path.exists(manifest_path):
                        try:
                            with open(manifest_path, "r", encoding="utf-8") as mf:
                                manifest_data = json.load(mf)
                        except Exception:
                            manifest_data = {"items": []}
                    items = manifest_data.get("items", [])
                    items = [it for it in items if it.get("target_path") != os.path.abspath(target_path)]
                    items.append({
                        "target_path": os.path.abspath(target_path),
                        "output_path": os.path.abspath(output_path),
                        "filename": filename,
                        "source_path": os.path.abspath(source_path) if source_path else ""
                    })
                    manifest_data["items"] = items
                    with open(manifest_path, "w", encoding="utf-8") as mf:
                        json.dump(manifest_data, mf, indent=2, ensure_ascii=False)
                except Exception as me:
                    print(f"  -> Warning updating manifest: {me}")
            except Exception as e:
                print(f"  -> Error saving file: {e}")
        finally:
            if temp_target_path and os.path.exists(temp_target_path):
                try:
                    os.remove(temp_target_path)
                except Exception:
                    pass
                
    print("\nBatch processing complete.")


if __name__ == "__main__":
    main()
