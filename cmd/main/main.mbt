///|
fn usage() -> Unit {
  println("conllu — CoNLL-U / Universal Dependencies toolkit")
  println("")
  println("Usage:")
  println("  conllu stats <file>              corpus statistics")
  println("  conllu validate <file>          structural validation")
  println("  conllu eval <gold> <pred>       UAS / LAS of a predicted parse")
  println("  conllu labels <gold> <pred>     per-relation labelled accuracy")
  println(
    "  conllu roundtrip <file>         parse + serialize, report the diff",
  )
  println(
    "  conllu dump <file>              stable row dump, for differential testing",
  )
}

///|
fn[T] fail(message : String) -> T {
  println("error: \{message}")
  @env.exit(1)
}

///|
fn read(path : String) -> String {
  @fs.read_file_to_string(path) catch {
    _ => fail("cannot read \{path}")
  }
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
fn cmd_labels(gold_path : String, pred_path : String) -> Unit {
  let gold = load(gold_path)
  let pred = load(pred_path)
  let scores = @conllu.evaluate_by_label(gold, pred)
  println("label                 gold  correct    las")
  for s in scores {
    let las = (s.las() * 100.0).to_int().to_double() / 100.0
    println(
      "\{pad_right(s.label, 20)} \{pad(s.gold.to_string(), 5)} \{pad(s.correct.to_string(), 8)} \{las}%",
    )
  }
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
      if args.length() != 4 {
        usage()
        @env.exit(2)
      } else {
        cmd_eval(args.at(2), args.at(3))
      }
    "labels" =>
      if args.length() != 4 {
        usage()
        @env.exit(2)
      } else {
        cmd_labels(args.at(2), args.at(3))
      }
    "dump" =>
      if args.length() != 3 {
        usage()
        @env.exit(2)
      } else {
        cmd_dump(args.at(2))
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
