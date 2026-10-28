"""Optional tree-sitter syntax check, not a Swift compiler or type checker.
Install pinned packages from validation-requirements.txt into .validation-python.
"""
from pathlib import Path
import json
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'.validation-python'))
from tree_sitter import Language, Parser
import tree_sitter_swift
parser=Parser(Language(tree_sitter_swift.language()))
failures=[]; files=[]
for file in [ROOT/'Package.swift', *sorted((ROOT/'Steady').glob('*.swift')), *sorted((ROOT/'Tests').glob('*.swift'))]:
    text=file.read_bytes(); tree=parser.parse(text); files.append(str(file.relative_to(ROOT)))
    def walk(node):
        if node.type=='ERROR' or node.is_missing:
            failures.append({'file':str(file.relative_to(ROOT)),'line':node.start_point.row+1,'type':node.type,'text':text[node.start_byte:node.end_byte].decode(errors='replace')[:180]})
        for child in node.children: walk(child)
    walk(tree.root_node)
result={'status':'FAIL' if failures else 'PASS','parser':'tree-sitter 0.26.0 / tree-sitter-swift 0.7.4','files':files,'failures':failures,'scope':'Grammar parsing only; no Swift name resolution, type checking, linking or XCTest execution.'}
(ROOT/'Validation/swift-syntax-results.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
sys.exit(bool(failures))
