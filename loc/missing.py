import argparse
import copy
import xml.etree.ElementTree as ET
from pathlib import Path

def find_missing_target_translations(input_filepath, output_filepath=""):
    """
    Parses an XLIFF XML file, finds <trans-unit> elements with missing <target>
    children, and writes these <trans-unit> elements to a new XML file,
    preserving the XLIFF structure and handling namespaces correctly to avoid ns0: prefixes.
    """
    try:
        parser = ET.XMLParser(encoding="utf-8")
        tree = ET.parse(input_filepath, parser=parser)
        original_root = tree.getroot()
    except FileNotFoundError:
        print(f"Error: Input file '{input_filepath}' not found.")
        return
    except ET.ParseError as e:
        print(f"Error: Could not parse XML file '{input_filepath}'. {e}")
        return

    # Define XLIFF 1.2 namespace URI
    xliff_ns_uri = "urn:oasis:names:tc:xliff:document:1.2"
    # Define XSI namespace URI (for xsi:schemaLocation)
    xsi_ns_uri = "http://www.w3.org/2001/XMLSchema-instance"

    # Register namespaces with ElementTree to control serialization
    # For the default XLIFF namespace, register an empty prefix
    ET.register_namespace('', xliff_ns_uri)
    # For the XSI namespace, register the 'xsi' prefix
    ET.register_namespace('xsi', xsi_ns_uri)


    # Create the root element for the output XML, copying tag and attributes
    # original_root.tag will be like "{urn:oasis:names:tc:xliff:document:1.2}xliff"
    # original_root.attrib will include xmlns attributes and others like version, xsi:schemaLocation
    output_root = ET.Element(original_root.tag, original_root.attrib)
    # Ensure the default xmlns attribute is correctly set if it wasn't through original_root.attrib
    # (though it should be). This is more of a safeguard.
    # If 'xmlns' is not already in output_root.attrib (it should be from original_root.attrib),
    # or if you want to be absolutely explicit:
    #if 'xmlns' not in output_root.attrib or output_root.attrib['xmlns'] != xliff_ns_uri:
    #    output_root.set('xmlns', xliff_ns_uri)


    any_missing_overall = False

    # Prepare namespaced tag strings for finding elements
    file_tag_ns = f"{{{xliff_ns_uri}}}file"
    body_tag_ns = f"{{{xliff_ns_uri}}}body"
    trans_unit_tag_ns = f"{{{xliff_ns_uri}}}trans-unit"
    target_tag_ns = f"{{{xliff_ns_uri}}}target"
    header_tag_ns = f"{{{xliff_ns_uri}}}header"

    for original_file_element in original_root.findall(file_tag_ns):
        missing_trans_units_for_this_file = []

        original_body = original_file_element.find(body_tag_ns)
        if original_body is not None:
            for trans_unit in original_body.findall(trans_unit_tag_ns):
                if trans_unit.find(target_tag_ns) is None and trans_unit.attrib.get('translate') != 'no':
                    missing_trans_units_for_this_file.append(copy.deepcopy(trans_unit))
                    any_missing_overall = True

        if missing_trans_units_for_this_file:
            # Create the <file> element in the output_root
            # original_file_element.tag is already namespaced correctly
            output_file_element = ET.SubElement(output_root,
                                                original_file_element.tag,
                                                original_file_element.attrib)

            original_header = original_file_element.find(header_tag_ns)
            if original_header is not None:
                output_file_element.append(copy.deepcopy(original_header))

            # Use the original body tag (which will be namespaced)
            output_body_element_tag = original_body.tag if original_body is not None else body_tag_ns
            output_body_element = ET.SubElement(output_file_element, output_body_element_tag)

            for unit in missing_trans_units_for_this_file:
                output_body_element.append(unit)

    if not any_missing_overall:
        print(f"No <trans-unit> elements with missing <target> found in '{input_filepath}'.")

    output_tree = ET.ElementTree(output_root)

    try:
        ET.indent(output_root, space="  ", level=0)
    except AttributeError:
        print("Note: ET.indent for pretty printing not available (requires Python 3.9+). Output will not be indented.")
        pass

    try:
        if not output_filepath:
            path = Path(input_filepath)
            output_filepath = str(path.with_name(f"missing-{path.name}"))

        # The ET.register_namespace calls above will guide the serializer
        output_tree.write(output_filepath, encoding='UTF-8', xml_declaration=True,
                          short_empty_elements=True) # Use short empty tags like <tool ... />
        if any_missing_overall:
            print(f"Found <trans-unit> elements with missing <target>. They have been written to '{output_filepath}'.")
        else:
             if not output_root.findall(file_tag_ns) and not any_missing_overall: # Check if any <file> elements were added
                print(f"Empty XLIFF structure written to '{output_filepath}' as no relevant content was found.")
             elif not any_missing_overall:
                print(f"Output file '{output_filepath}' written, but contained no missing target units.")

    except IOError as e:
        print(f"Error: Could not write to output file '{output_filepath}'. {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Finds <trans-unit> elements with missing <target> in an XLIFF XML file and writes them to a new file."
    )
    parser.add_argument(
        "input_file",
        help="Path to the input XLIFF XML file (e.g., es.xliff)"
    )
    parser.add_argument(
        "output_file",
        default="",
        help="Path to the output file (e.g., es.xml)"
    )
    args = parser.parse_args()

    find_missing_target_translations(args.input_file, args.output_file)
