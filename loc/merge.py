import xml.etree.ElementTree as ET
import argparse
import os
import copy

# Define the XLIFF namespace to correctly find elements and preserve it on output
XLIFF_NAMESPACE = "urn:oasis:names:tc:xliff:document:1.2"
# For findall, it's often easier to use a prefix map
NS_MAP = {'xliff': XLIFF_NAMESPACE}

def patch_xliff_file(source_file_path, dest_file_path):
    """
    Patches a destination XLIFF file with <trans-unit> tags from a source XLIFF file.

    Args:
        source_file_path (str): Path to the source XLIFF file.
        dest_file_path (str): Path to the destination XLIFF file.
    """

    # Register the default namespace for proper output serialization.
    # This ensures xmlns="urn:oasis:names:tc:xliff:document:1.2" is used
    # instead of something like ns0="urn:oasis:names:tc:xliff:document:1.2".
    ET.register_namespace('', XLIFF_NAMESPACE)

    try:
        source_tree = ET.parse(source_file_path)
        source_root = source_tree.getroot()
    except FileNotFoundError:
        print(f"Error: Source file not found: {source_file_path}")
        return
    except ET.ParseError as e:
        print(f"Error: Could not parse source XML file '{source_file_path}': {e}")
        return

    try:
        dest_tree = ET.parse(dest_file_path)
        dest_root = dest_tree.getroot()
    except FileNotFoundError:
        print(f"Error: Destination file not found: {dest_file_path}")
        return
    except ET.ParseError as e:
        print(f"Error: Could not parse destination XML file '{dest_file_path}': {e}")
        return

    # 1. Collect all trans-units from the source file into a dictionary by ID
    source_trans_units = {}
    # Search for trans-unit elements anywhere under the root, respecting the namespace
    for trans_unit_element in source_root.findall('.//xliff:trans-unit', NS_MAP):
        unit_id = trans_unit_element.get('id')
        if unit_id:
            source_trans_units[unit_id] = trans_unit_element
            # print(f"Source: Found <trans-unit id='{unit_id}'>") # Optional: for debugging

    if not source_trans_units:
        print("Warning: No <trans-unit> elements with IDs found in the source file.")
        # We can still proceed, as it might just mean no replacements will occur.

    # 2. Create a parent map for the destination tree.
    # This is crucial for replacing elements, as ElementTree elements don't store parent pointers by default.
    parent_map = {c: p for p in dest_tree.iter() for c in p}

    replaced_count = 0
    not_found_in_source_count = 0

    # 3. Iterate through trans-units in the destination file and replace if a match is found in source.
    # We need to iterate carefully if modifying the tree.
    # Finding all relevant units first, then processing them is safer.
    dest_units_to_process = list(dest_root.findall('.//xliff:trans-unit', NS_MAP))

    for dest_trans_unit in dest_units_to_process:
        dest_unit_id = dest_trans_unit.get('id')

        if dest_unit_id and dest_unit_id in source_trans_units:
            source_unit_to_insert = source_trans_units[dest_unit_id]
            parent = parent_map.get(dest_trans_unit)

            if parent is not None:
                # Get the index of the old element within its parent
                try:
                    # Children of parent can be accessed by iterating parent or parent._children (internal)
                    # A robust way is to convert parent's children to a list to find the index
                    children_list = list(parent)
                    index = children_list.index(dest_trans_unit)

                    # Remove old element
                    parent.remove(dest_trans_unit)

                    # Insert a deep copy of the source element.
                    # This is important because the source element belongs to another tree,
                    # and simply inserting it might lead to issues or modifications in the source tree
                    # if it were to be used elsewhere. Deepcopy ensures it's a fresh element.
                    new_element = copy.deepcopy(source_unit_to_insert)
                    parent.insert(index, new_element)

                    print(f"Replaced <trans-unit id='{dest_unit_id}'>")
                    replaced_count += 1
                except ValueError:
                    # This should theoretically not happen if dest_trans_unit was found
                    # via findall and is part of the parent_map.
                    print(f"Error: Could not find <trans-unit id='{dest_unit_id}'> in its parent's children list. Skipping.")
            else:
                # This would typically only happen if the trans-unit is the root element,
                # which is not standard for XLIFF <trans-unit>.
                print(f"Warning: Could not find parent for <trans-unit id='{dest_unit_id}'>. Skipping.")
        elif dest_unit_id:
            # print(f"Info: <trans-unit id='{dest_unit_id}'> in destination not found in source. Kept as is.") # Optional
            not_found_in_source_count +=1


    print(f"\nPatching summary:")
    print(f"  Total <trans-unit> elements processed in destination: {len(dest_units_to_process)}")
    print(f"  <trans-unit> elements replaced: {replaced_count}")
    if not_found_in_source_count > 0:
        print(f"  <trans-unit> elements in destination not found in source (and thus kept): {not_found_in_source_count}")


    # 4. Write the modified destination tree to a new file
    base, ext = os.path.splitext(dest_file_path)
    output_file_path = f"{base}-patch{ext}"

    try:
        dest_tree.write(output_file_path, encoding='UTF-8', xml_declaration=True)
        print(f"Successfully wrote patched file to: {output_file_path}")
    except Exception as e:
        print(f"Error writing output file '{output_file_path}': {e}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Patches a destination XLIFF file with <trans-unit> tags "
                    "from a source XLIFF file based on matching IDs. "
                    "The output is written to 'destination_filename-patch.ext'."
    )
    parser.add_argument("source_xml", help="Path to the source XLIFF file.")
    parser.add_argument("destination_xml", help="Path to the destination XLIFF file to be patched.")

    args = parser.parse_args()

    # Create a dummy destination file for testing if it doesn't exist
    # For a real scenario, you'd have your actual destination file.
    # if not os.path.exists(args.destination_xml) and args.source_xml == "missing-es.xml":
    #     print(f"Creating a dummy destination file '{args.destination_xml}' for testing purposes.")
    #     dummy_dest_content = f"""<?xml version='1.0' encoding='UTF-8'?>
    # <xliff xmlns="urn:oasis:names:tc:xliff:document:1.2" version="1.2">
    #   <file original="en.lproj/Localizable.strings" source-language="en" target-language="es" datatype="plaintext">
    #     <body>
    #       <trans-unit id="Alias copied" xml:space="preserve">
    #         <source>Alias copied</source>
    #         <target>OLD ALIAS COPIED TARGET</target>
    #         <note>Toast notification</note>
    #       </trans-unit>
    #       <trans-unit id="Delete for me" xml:space="preserve">
    #         <source>Delete for me</source>
    #         <target>OLD DELETE FOR ME TARGET</target>
    #         <note>Menu item</note>
    #       </trans-unit>
    #       <trans-unit id="NonExistentInSource" xml:space="preserve">
    #         <source>This one is not in source</source>
    #         <target>TARGET FOR NON-EXISTENT</target>
    #         <note>Test case</note>
    #       </trans-unit>
    #     </body>
    #   </file>
    #   <file original="Pods/en.lproj/Localizable.strings" datatype="plaintext" source-language="en" target-language="es">
    #     <body>
    #       <trans-unit id="Phone number is ambiguous." xml:space="preserve">
    #         <source>Phone number is ambiguous.</source>
    #         <target>OLD PHONE AMBIGUOUS TARGET</target>
    #         <note>No comment provided by engineer.</note>
    #       </trans-unit>
    #     </body>
    #   </file>
    # </xliff>"""
    #     with open(args.destination_xml, "w", encoding="utf-8") as f:
    #         f.write(dummy_dest_content)

    patch_xliff_file(args.source_xml, args.destination_xml)