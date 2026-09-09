"""Structural publication edits must preserve list content and ordering."""

from publications.chapter_reference import blocks_from_markdown


def test_nested_lists_and_wrapped_paragraphs_preserve_hierarchy():
    blocks = blocks_from_markdown(
        "- Configure the controller\n  before starting.\n"
        "  - Wait for READY.\n  - Clear ERROR.\n"
        "- Start the transfer.\n\nA separate paragraph."
    )
    outer = blocks[0]
    assert outer["kind"] == "list" and not outer["ordered"]
    assert len(outer["items"]) == 2
    first = outer["items"][0]["blocks"]
    assert first[0]["text"] == "Configure the controller before starting."
    assert [i["blocks"][0]["text"] for i in first[1]["items"]] == [
        "Wait for READY.", "Clear ERROR."
    ]
    assert blocks[1]["text"] == "A separate paragraph."


def test_explicit_numbers_and_mixed_list_kinds_are_preserved():
    blocks = blocks_from_markdown("3. First step\n7. Later step\n- A bullet\n+ Another bullet")
    assert [i["number"] for i in blocks[0]["items"]] == [3, 7]
    assert blocks[1]["ordered"] is False
    assert len(blocks[1]["items"]) == 2


def test_code_inside_list_is_not_parsed_as_nested_bullets():
    blocks = blocks_from_markdown("- Run:\n  ```c\n  - not_a_list;\n  ```\n- Finish.")
    code = blocks[0]["items"][0]["blocks"][1]
    assert code == {"kind": "code", "language": "c", "text": "- not_a_list;"}
    assert len(blocks[0]["items"]) == 2


def test_blank_separated_items_and_lazy_continuations_keep_their_text():
    blocks = blocks_from_markdown("1. Wait for READY\nand check ERROR.\n\n2. Start.\n\n## Next")
    assert blocks[0]["items"][0]["blocks"][0]["text"] == "Wait for READY and check ERROR."
    assert blocks[0]["items"][1]["blocks"][0]["text"] == "Start."
    assert blocks[1] == {"kind": "heading", "text": "Next"}
