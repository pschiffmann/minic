library minic.transformer.render_instruction_docs;

import 'package:analyzer/analyzer.dart' show parseCompilationUnit, EnumDeclaration, EnumConstantDeclaration, Comment;
import 'package:barback/barback.dart';
import 'package:markdown/markdown.dart';
import 'package:mustache/mustache.dart' show Template;
import 'dart:async';

final AssetId dartSource = new AssetId('minic', 'lib/src/cmachine.dart');
final AssetId mustacheSource = new AssetId('minic', 'lib/transformer/instruction_doc_template.html');
final AssetId outputFile = new AssetId('minic', 'lib/html/instructions.html');

/// This transformer generates an html file of all [InstructionCode] comments
/// for use in the UI.
class RenderInstructionDocs extends Transformer {
  RenderInstructionDocs.asPlugin();

  Future<bool> isPrimary(AssetId id) {
    return new Future.value(id == dartSource);
  }

  Future apply(Transform transform) async {
    var source = parseCompilationUnit(
        await transform.primaryInput.readAsString(),
        name: dartSource.path,
        parseFunctionBodies: true);
    EnumDeclaration instructionCodeEnum = source.declarations.firstWhere(
        (u) => (u as EnumDeclaration)?.name?.name == 'InstructionCode');

    var formattedDocs = [];
    for (EnumConstantDeclaration c in instructionCodeEnum.constants) {
      formattedDocs.add({
        'name': c.name.name,
        'content': renderComment(c.documentationComment)
      });
    }

    Template template = new Template(await transform.readInputAsString(mustacheSource), name: mustacheSource.path);
    transform.addOutput(new Asset.fromString(
      outputFile,
      template.renderString({'instructions': formattedDocs})
    ));
  }

  /// Render the given [comment] into a string.
  String renderComment(Comment comment) {
    return markdownToHtml(comment.childEntities.map((child) {
      var str = child.toString();
      return str.length > 4 ? str.substring(4) : '';
    }).join('\n'));
  }
}
