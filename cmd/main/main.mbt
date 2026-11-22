///|
fn usage() -> Unit {
  println("conllu — CoNLL-U / Universal Dependencies toolkit")
  println("")
  println("Usage:")
  println("  conllu stats <file>              corpus statistics")
  println("  conllu validate <file>          structural validation")
  println(
    "  conllu eval <gold> <pred>       UAS / LAS of a predicted parse (--by-document)",
  )
  println(
    "  conllu labels <gold> <pred>     per-relation labelled accuracy (--format csv)",
  )
  println(
    "  conllu roundtrip <file>         parse + serialize, report the diff",
  )
  println(
    "  conllu dump <file>              stable row dump, for differential testing",
  )
  println("  conllu docs <file>              document and paragraph structure")
  println(
    "  conllu analyze <file>...        coverage report: tags, trees, sentence shapes",
  )
  println(
    "  conllu compress <in> <out>      serialize and write back, gzip when <out> ends in .gz",
  )
  println("")
  println("<file> may be plain text or gzipped (`.conllu.gz`).")
}

///|
fn[T] fail(message : String) -> T {
  println("error: \{message}")
  @env.exit(1)
}

///|
/// Reads a treebank as UTF-8 text. Files ending in `.gz` are inflated with the
/// core gzip implementation, so a compressed treebank works without unzipping
/// it first.
fn read(path : String) -> String {
  if path.has_suffix(".gz") {
    let bytes = @fs.read_file_to_bytes(path) catch {
      _ => fail("cannot read \{path}")
    }
    let plain = @gzip.decompress(bytes) catch {
      _ => fail("cannot decompress \{path}")
    }
    @utf8.decode(plain) catch {
      _ => fail("\{path}: not valid UTF-8")
    }
  } else {
    @fs.read_file_to_string(path) catch {
      _ => fail("cannot read \{path}")
    }
  }
}

///|
/// Writes `text` as UTF-8 bytes, gzip-compressed when `path` ends in `.gz`. This
/// is the counterpart of `read`, so a treebank that arrived compressed can be
/// written back compressed without expanding it to disk first.
fn write_text(path : String, text : String) -> Unit {
  let bytes = @utf8.encode(text)
  let payload = if path.has_suffix(".gz") {
    @gzip.compress(bytes)
  } else {
    bytes
  }
  @fs.write_bytes_to_file(path, payload) catch {
    _ => fail("cannot write \{path}")
  }
}

///|
fn file_size(path : String) -> Int32 {
  let bytes = @fs.read_file_to_bytes(path) catch {
    _ => fail("cannot read \{path}")
  }
  bytes.length()
}

///|
/// Last path segment, so a table stays readable when the inputs are long paths.
fn basename(path : String) -> String {
  let parts = replace_all(path, "\\", "/").split("/").to_array()
  if parts.length() == 0 {
    path
  } else {
    parts.at(parts.length() - 1).to_owned()
  }
}

///|
/// Coverage report. One file prints the full report; several files print one
/// row per file plus a merged TOTAL row, which is how dev and test splits get
/// compared without running the command twice by hand. Exits non-zero when the
/// corpus uses tags or relations the UD spec does not define, so the command
/// doubles as a corpus gate.
fn cmd_analyze(paths : Array[String]) -> Unit {
  if paths.length() == 1 {
    let cov = @conllu.coverage(load(paths.at(0)))
    println(cov.to_string())
    if cov.unknown_upos.length() > 0 || cov.unknown_deprel.length() > 0 {
      @env.exit(1)
    }
    return
  }
  let coverages : Array[@conllu.Coverage] = []
  for path in paths {
    coverages.push(@conllu.coverage(load(path)))
  }
  println(
    "file                            sentences   words  upos deprel unknown projective  depth",
  )
  let mut i = 0
  while i < paths.length() {
    print_coverage_row(basename(paths.at(i)), coverages.at(i))
    i = i + 1
  }
  let merged = @conllu.merge_coverage(coverages)
  print_coverage_row("TOTAL", merged)
  if merged.unknown_upos.length() > 0 || merged.unknown_deprel.length() > 0 {
    @env.exit(1)
  }
}

///|
fn print_coverage_row(name : String, cov : @conllu.Coverage) -> Unit {
  let upos = "\{cov.upos_used.length()}/\{17}"
  let deprel = "\{cov.deprel_used.length()}/\{37}"
  let unknown = cov.unknown_upos.length() + cov.unknown_deprel.length()
  println(
    "\{pad_right(name, 30)} \{pad(cov.sentences.to_string(), 9)} \{pad(cov.words.to_string(), 7)} \{pad(upos, 5)} \{pad(deprel, 6)} \{pad(unknown.to_string(), 7)} \{pad(pct(cov.projectivity()) + "%", 10)} \{pad(cov.max_depth.to_string(), 6)}",
  )
}

///|
/// Prints the document / paragraph tree implied by `# newdoc` and `# newpar`
/// lines, plus the sentence counts on each level.
fn cmd_docs(path : String) -> Unit {
  let docs = @conllu.documents(load(path))
  let mut paragraphs = 0
  let mut i = 0
  while i < docs.length() {
    let doc = docs.at(i)
    paragraphs = paragraphs + doc.paragraph_count()
    let id = if doc.id().is_empty() { "-" } else { doc.id() }
    println(
      "doc \{pad((i + 1).to_string(), 4)} id=\{pad_right(id, 24)} sentences=\{pad(doc.sentence_count().to_string(), 5)} paragraphs=\{doc.paragraph_count()}",
    )
    if doc.paragraph_count() > 1 {
      let mut j = 0
      for par in doc.paragraphs() {
        j = j + 1
        let pid = if par.id().is_empty() { "-" } else { par.id() }
        println("  par \{j}: id=\{pid} sentences=\{par.sentence_count()}")
      }
    }
    i = i + 1
  }
  println("documents=\{docs.length()} paragraphs=\{paragraphs}")
}

///|
/// Reads a treebank, serializes it with the canonical writer and writes it back,
/// compressing when the output path ends in `.gz`. The result is read again and
/// compared with what was written, so a broken compression path fails loudly
/// instead of producing a file that only looks fine.
fn cmd_compress(input : String, output : String) -> Unit {
  let sentences = load(input)
  let rendered = @conllu.to_string(sentences)
  write_text(output, rendered)
  let back = read(output)
  if back != rendered {
    fail("self-check failed: \{output} does not read back identically")
  }
  let in_bytes = file_size(input)
  let out_bytes = file_size(output)
  let ratio = if in_bytes == 0 {
    0.0
  } else {
    out_bytes.to_double() / in_bytes.to_double() * 100.0
  }
  println(
    "compress: \{sentences.length()} sentences \{in_bytes} -> \{out_bytes} bytes (\{pct(ratio)}% of input)",
  )
  println("verify: \{output} reads back identically")
}

///|
fn load(path : String) -> Array[@conllu.Sentence] {
  let text = read(path)
  @conllu.parse(text) catch {
    @conllu.ConlluError(line, message) => fail("\{path}:\{line}: \{message}")
  }
}

///|
fn cmd_stats(path : String) -> Unit {
  let sentences = load(path)
  let diagnostics = @conllu.validate(sentences)
  let errors = @conllu.count_errors(diagnostics)
  let st = @conllu.stats(sentences)
  println(st.to_string())
  println("errors=\{errors}")
  if errors > 0 {
    @env.exit(1)
  }
}

///|
fn cmd_validate(path : String) -> Unit {
  let sentences = load(path)
  let diagnostics = @conllu.validate(sentences)
  for d in diagnostics {
    println(d.to_string())
  }
  let errors = @conllu.count_errors(diagnostics)
  println("diagnostics=\{diagnostics.length()} errors=\{errors}")
  if errors > 0 {
    @env.exit(1)
  }
}

///|
fn cmd_eval(gold_path : String, pred_path : String) -> Unit {
  let gold = load(gold_path)
  let pred = load(pred_path)
  let result = @conllu.evaluate(gold, pred)
  println(result.to_string())
  if result.aligned_tokens == 0 {
    @env.exit(1)
  }
}

///|
/// Quotes a CSV field only when it contains a comma or a quote, doubling inner
/// quotes as RFC 4180 wants. Relation names never need it, but a corpus that
/// labels something with a comma should not break the table.
fn csv_field(value : String) -> String {
  if value.contains(",") || value.contains("\"") {
    "\"" + replace_all(value, "\"", "\"\"") + "\""
  } else {
    value
  }
}

///|
/// Per-document scores: same alignment as `eval`, but grouped by the gold
/// `# newdoc` ids, worst document first, followed by the corpus total.
fn cmd_eval_by_document(gold_path : String, pred_path : String) -> Unit {
  let gold = load(gold_path)
  let pred = load(pred_path)
  let scores = @conllu.evaluate_by_document(gold, pred)
  println("doc                              sentences tokens    UAS     LAS")
  for score in scores {
    let id = if score.id().is_empty() { "-" } else { score.id() }
    println(
      "\{pad_right(id, 32)} \{pad(score.sentences().to_string(), 9)} \{pad(score.tokens().to_string(), 6)} \{pad(pct(score.uas()) + "%", 6)} \{pad(pct(score.las()) + "%", 6)}",
    )
  }
  let total = @conllu.evaluate(gold, pred)
  println("total: " + total.to_string())
  if total.aligned_tokens == 0 {
    @env.exit(1)
  }
}

///|
/// Per-relation labelled accuracy as a table or as CSV. The CSV form exists so
/// the numbers can be pasted into a spreadsheet or diffed between two runs
/// instead of being read off a terminal.
fn cmd_labels(gold_path : String, pred_path : String, csv : Bool) -> Unit {
  let gold = load(gold_path)
  let pred = load(pred_path)
  let scores = @conllu.evaluate_by_label(gold, pred)
  if csv {
    println("label,gold,correct,las")
    for s in scores {
      println("\{csv_field(s.label)},\{s.gold},\{s.correct},\{pct(s.las())}")
    }
    return
  }
  println("label                 gold  correct    las")
  for s in scores {
    println(
      "\{pad_right(s.label, 20)} \{pad(s.gold.to_string(), 5)} \{pad(s.correct.to_string(), 8)} \{pct(s.las())}%",
    )
  }
}

///|
/// Formats a percentage with two decimals, as `94.29`.
fn pct(value : Double) -> String {
  let rounded = (value * 100.0).to_int().to_double() / 100.0
  rounded.to_string()
}

///|
/// Left-pads `value` with spaces so numeric columns stay aligned.
fn pad(value : String, width : Int32) -> String {
  let mut out = value
  while out.length() < width {
    out = " " + out
  }
  out
}

///|
/// Right-pads `value` so the text column stays aligned.
fn pad_right(value : String, width : Int32) -> String {
  let mut out = value
  while out.length() < width {
    out = out + " "
  }
  out
}

///|
/// Replaces every occurrence of `from` with `to` (non-overlapping).
fn replace_all(value : String, from : String, to : String) -> String {
  let parts = value.split(from).to_array()
  let mut out = ""
  let mut i = 0
  while i < parts.length() {
    if i > 0 {
      out = out + to
    }
    out = out + parts.at(i).to_owned()
    i = i + 1
  }
  out
}

///|
/// Escapes a string for a JSON string literal. Only the characters that can
/// actually appear in CoNLL-U fields are handled; control characters below
/// U+0020 other than tab/newline/CR are not produced by the format.
fn json_escape(value : String) -> String {
  let mut s = replace_all(value, "\\", "\\\\")
  s = replace_all(s, "\"", "\\\"")
  s = replace_all(s, "\n", "\\n")
  s = replace_all(s, "\r", "\\r")
  s = replace_all(s, "\t", "\\t")
  s
}

///|
fn json_str(value : String) -> String {
  "\"" + json_escape(value) + "\""
}

///|
fn token_json(row : @conllu.Token) -> String {
  let kind = match row.kind {
    @conllu.Word => "word"
    @conllu.Multiword => "multiword"
    @conllu.Empty => "empty"
  }
  "{\"kind\":" +
  json_str(kind) +
  ",\"id\":" +
  json_str(row.id_raw) +
  ",\"form\":" +
  json_str(row.form) +
  ",\"lemma\":" +
  json_str(row.lemma) +
  ",\"upos\":" +
  json_str(row.upos) +
  ",\"xpos\":" +
  json_str(row.xpos) +
  ",\"feats\":" +
  json_str(row.feats) +
  ",\"head\":" +
  json_str(row.head_raw) +
  ",\"deprel\":" +
  json_str(row.deprel) +
  ",\"deps\":" +
  json_str(row.deps) +
  ",\"misc\":" +
  json_str(row.misc) +
  ",\"line\":" +
  row.line.to_string() +
  "}"
}

///|
/// Machine-readable form of `dump`: one JSON object for the whole file, with
/// every token keeping its raw column values. Used by wrappers in other
/// languages that do not want to parse the line-oriented dump.
fn cmd_dump_json(path : String) -> Unit {
  let sentences = load(path)
  let mut out = "{\"source\":" + json_str(path) + ",\"sentences\":["
  let mut i = 0
  while i < sentences.length() {
    let sentence = sentences.at(i)
    if i > 0 {
      out = out + ","
    }
    let mut multi = 0
    let mut empty = 0
    for row in sentence.rows() {
      if row.is_multiword() {
        multi = multi + 1
      }
      if row.is_empty_node() {
        empty = empty + 1
      }
    }
    out = out +
      "{\"line\":" +
      sentence.line.to_string() +
      ",\"words\":" +
      sentence.word_count().to_string() +
      ",\"multiword\":" +
      multi.to_string() +
      ",\"empty\":" +
      empty.to_string() +
      ",\"comments\":["
    let mut c = 0
    for comment in sentence.comments() {
      if c > 0 {
        out = out + ","
      }
      out = out + json_str(comment)
      c = c + 1
    }
    out = out + "],\"tokens\":["
    let mut t = 0
    for row in sentence.rows() {
      if t > 0 {
        out = out + ","
      }
      out = out + token_json(row)
      t = t + 1
    }
    out = out + "]}"
    i = i + 1
  }
  out = out + "]}"
  println(out)
}

///|
/// Emits one line per row in a stable, diff-friendly format:
///   S <words> <multiword> <empty> <comments>
///   <kind> <id> <form> <upos> <head> <deprel>
/// Used by the differential harness in `tools/`.
fn cmd_dump(path : String) -> Unit {
  let sentences = load(path)
  println("D \{sentences.length()}")
  for sentence in sentences {
    let mut multi = 0
    let mut empty = 0
    for row in sentence.rows() {
      if row.is_multiword() {
        multi = multi + 1
      }
      if row.is_empty_node() {
        empty = empty + 1
      }
    }
    println(
      "S \{sentence.word_count()} \{multi} \{empty} \{sentence.comments().length()}",
    )
    for row in sentence.rows() {
      let kind = match row.kind {
        @conllu.Word => "w"
        @conllu.Multiword => "m"
        @conllu.Empty => "e"
      }
      println(
        "\{kind} \{row.id_raw} \{row.form} \{row.upos} \{row.head_raw} \{row.deprel}",
      )
    }
  }
}

///|
fn cmd_roundtrip(path : String) -> Unit {
  let text = read(path)
  let sentences = @conllu.parse(text) catch {
    @conllu.ConlluError(line, message) => fail("\{path}:\{line}: \{message}")
  }
  let rendered = @conllu.to_string(sentences)
  if rendered == text {
    println("roundtrip: identical (\{sentences.length()} sentences)")
    return
  }
  // The serializer always terminates the last sentence with a blank line, so a
  // file that only lacks that terminator is still a lossless round-trip.
  if rendered == text + "\n" {
    println(
      "roundtrip: identical up to the canonical trailing blank line (\{sentences.length()} sentences)",
    )
    return
  }
  let input_lines = text.split("\n").to_array()
  let output_lines = rendered.split("\n").to_array()
  let mut i = 0
  let mut reported = 0
  let max = if input_lines.length() < output_lines.length() {
    input_lines.length()
  } else {
    output_lines.length()
  }
  while i < max {
    if input_lines.at(i) != output_lines.at(i) {
      if reported < 3 {
        println("diff at line \{i + 1}:")
        println("  input: \{input_lines.at(i)}")
        println("  output: \{output_lines.at(i)}")
      }
      reported = reported + 1
    }
    i = i + 1
  }
  if input_lines.length() != output_lines.length() {
    reported = reported + 1
    println(
      "line count differs: input=\{input_lines.length()} output=\{output_lines.length()}",
    )
  }
  println("roundtrip: \{reported} line(s) differ")
  @env.exit(1)
}

///|
fn main {
  let args = @env.args()
  if args.length() < 2 {
    usage()
    @env.exit(2)
  }
  let command = args.at(1)
  match command {
    "stats" =>
      if args.length() != 3 {
        usage()
        @env.exit(2)
      } else {
        cmd_stats(args.at(2))
      }
    "validate" =>
      if args.length() != 3 {
        usage()
        @env.exit(2)
      } else {
        cmd_validate(args.at(2))
      }
    "eval" =>
      if args.length() == 4 {
        cmd_eval(args.at(2), args.at(3))
      } else if args.length() == 5 && args.at(4) == "--by-document" {
        cmd_eval_by_document(args.at(2), args.at(3))
      } else {
        usage()
        @env.exit(2)
      }
    "labels" =>
      if args.length() == 4 {
        cmd_labels(args.at(2), args.at(3), false)
      } else if args.length() == 6 && args.at(4) == "--format" {
        if args.at(5) == "csv" {
          cmd_labels(args.at(2), args.at(3), true)
        } else if args.at(5) == "text" {
          cmd_labels(args.at(2), args.at(3), false)
        } else {
          fail("unknown labels format \{args.at(5)} (expected text or csv)")
        }
      } else if args.length() == 5 && args.at(4) == "--format=csv" {
        cmd_labels(args.at(2), args.at(3), true)
      } else {
        usage()
        @env.exit(2)
      }
    "dump" =>
      if args.length() == 3 {
        cmd_dump(args.at(2))
      } else if args.length() == 5 && args.at(3) == "--format" {
        if args.at(4) == "json" {
          cmd_dump_json(args.at(2))
        } else if args.at(4) == "text" {
          cmd_dump(args.at(2))
        } else {
          fail("unknown dump format \{args.at(4)} (expected text or json)")
        }
      } else if args.length() == 4 && args.at(3) == "--format=json" {
        cmd_dump_json(args.at(2))
      } else {
        usage()
        @env.exit(2)
      }
    "analyze" =>
      if args.length() < 3 {
        usage()
        @env.exit(2)
      } else {
        let paths : Array[String] = []
        let mut i = 2
        while i < args.length() {
          paths.push(args.at(i))
          i = i + 1
        }
        cmd_analyze(paths)
      }
    "docs" =>
      if args.length() != 3 {
        usage()
        @env.exit(2)
      } else {
        cmd_docs(args.at(2))
      }
    "compress" =>
      if args.length() != 4 {
        usage()
        @env.exit(2)
      } else {
        cmd_compress(args.at(2), args.at(3))
      }
    "roundtrip" =>
      if args.length() != 3 {
        usage()
        @env.exit(2)
      } else {
        cmd_roundtrip(args.at(2))
      }
    "-h" | "--help" | "help" => usage()
    _ => {
      println("error: unknown command \{command}")
      usage()
      @env.exit(2)
    }
  }
}
