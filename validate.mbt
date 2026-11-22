///|
/// Severity of a validation diagnostic.
pub(all) enum Severity {
  Error
  Warning
}

///|
/// One validation finding, tied to a physical line of the source file.
pub struct Diagnostic {
  line : Int32
  severity : Severity
  code : String
  message : String
}

///|
pub fn Diagnostic::to_string(self : Diagnostic) -> String {
  let level = match self.severity {
    Error => "error"
    Warning => "warning"
  }
  "line \{self.line}: \{level} [\{self.code}] \{self.message}"
}

///|
/// One diagnostic as a JSON object, for CI steps that need to filter by code
/// instead of regexing `line 12: error [ROOT_COUNT] ...`.
pub fn Diagnostic::to_json(self : Diagnostic) -> String {
  let level = match self.severity {
    Error => "error"
    Warning => "warning"
  }
  "{\"line\":" +
  self.line.to_string() +
  ",\"severity\":" +
  json_str(level) +
  ",\"code\":" +
  json_str(self.code) +
  ",\"message\":" +
  json_str(self.message) +
  "}"
}

///|
/// A diagnostic list as a JSON array.
pub fn diagnostics_to_json(diagnostics : Array[Diagnostic]) -> String {
  let mut out = "["
  let mut i = 0
  while i < diagnostics.length() {
    if i > 0 {
      out = out + ","
    }
    out = out + diagnostics.at(i).to_json()
    i = i + 1
  }
  out + "]"
}

///|
/// The 17 universal part-of-speech tags of UD v2.
let upos_tags : Array[String] = [
  "ADJ", "ADP", "ADV", "AUX", "CCONJ", "DET", "INTJ", "NOUN", "NUM", "PART", "PRON",
  "PROPN", "PUNCT", "SCONJ", "SYM", "VERB", "X",
]

///|
/// The 37 universal dependency relations of UD v2.
let deprel_tags : Array[String] = [
  "acl", "advcl", "advmod", "amod", "appos", "aux", "case", "cc", "ccomp", "clf",
  "compound", "conj", "cop", "csubj", "dep", "det", "discourse", "dislocated", "expl",
  "fixed", "flat", "goeswith", "iobj", "list", "mark", "nmod", "nsubj", "nummod",
  "obj", "obl", "orphan", "parataxis", "punct", "reparandum", "root", "vocative",
  "xcomp",
]

///|
fn base_deprel(deprel : String) -> String {
  match deprel.split_once(":") {
    Some((base, _)) => base.to_owned()
    None => deprel
  }
}

///|
/// Enhanced DEPS may use relations that never appear in the basic tree, most
/// notably `ref` for the antecedent of a relative pronoun.
fn is_valid_enhanced_deprel(deprel : String) -> Bool {
  base_deprel(deprel) == "ref" || is_valid_deprel(deprel)
}

///|
fn is_valid_deprel(deprel : String) -> Bool {
  if deprel.is_empty() || deprel == "_" {
    return false
  }
  let base = base_deprel(deprel)
  if base == "root" {
    return deprel == "root"
  }
  deprel_tags.contains(base)
}

///|
fn push(
  out : Array[Diagnostic],
  line : Int32,
  severity : Severity,
  code : String,
  message : String,
) -> Unit {
  out.push({ line, severity, code, message, })
}

///|
/// Checks the structure of one sentence: ID sequence, HEAD targets, single
/// root, acyclicity, DEPS syntax, tag sets and token surface constraints.
/// Lexical errors are already rejected by `parse`, so everything reported here
/// keeps a sentence inspectable.
pub fn validate_sentence(sentence : Sentence) -> Array[Diagnostic] {
  let out : Array[Diagnostic] = []
  let words = sentence.words()
  let n = words.length()
  if n == 0 {
    push(
      out,
      sentence.line,
      Error,
      "EMPTY_SENTENCE",
      "sentence has no word rows",
    )
    return out
  }
  // 1. Word IDs must be exactly 1..n, in order.
  let mut expected : Int32 = 1
  for row in sentence.rows {
    if row.kind is Word {
      if row.start != expected {
        push(
          out,
          row.line,
          Error,
          "ID_SEQUENCE",
          "word ID \{row.start} found where \{expected} was expected",
        )
      }
      expected = expected + 1
    }
  }
  // 2. Multiword rows must precede the words they cover and stay in range.
  for row in sentence.rows {
    if row.kind is Multiword {
      if row.start < 1 || row.end > n {
        push(
          out,
          row.line,
          Error,
          "MULTIWORD_SPAN",
          "multiword token \{row.id_raw} covers IDs outside 1..\{n}",
        )
      }
    }
  }
  // 3. HEAD on every word row: numeric, in range, not self, one root.
  let mut roots : Int32 = 0
  for row in words {
    let head = row.head()
    match head {
      None =>
        push(
          out,
          row.line,
          Error,
          "HEAD_MISSING",
          "word row must have a numeric HEAD",
        )
      Some(h) =>
        if h < 0 || h > n {
          push(
            out,
            row.line,
            Error,
            "HEAD_RANGE",
            "HEAD \{h} is outside 0..\{n}",
          )
        } else if h == row.start {
          push(
            out,
            row.line,
            Error,
            "HEAD_SELF",
            "token \{row.start} is its own head",
          )
        } else if h == 0 {
          roots = roots + 1
        }
    }
    if row.form.is_empty() {
      push(out, row.line, Error, "FORM_EMPTY", "FORM must not be empty")
    }
    if row.form.contains(" ") || row.form.contains("\t") {
      push(
        out,
        row.line,
        Error,
        "FORM_SPACE",
        "a word FORM must not contain whitespace",
      )
    }
    if !upos_tags.contains(row.upos) {
      push(out, row.line, Error, "UPOS_UNKNOWN", "unknown UPOS tag \{row.upos}")
    }
    if !is_valid_deprel(row.deprel) {
      push(
        out,
        row.line,
        Error,
        "DEPREL_UNKNOWN",
        "unknown DEPREL \{row.deprel}",
      )
    }
    validate_deps(out, row, n)
  }
  if roots != 1 {
    push(
      out,
      sentence.line,
      Error,
      "ROOT_COUNT",
      "sentence has \{roots} roots, exactly one is required",
    )
  }
  // 4. No cycles: walking HEAD from every word must reach the root.
  for row in words {
    let mut cur = row.start
    let mut steps : Int32 = 0
    let mut ok = false
    while steps <= n {
      match words.at(cur - 1).head() {
        Some(0) => {
          ok = true
          break
        }
        Some(h) => if h < 0 || h > n || h == cur { break } else { cur = h }
        None => break
      }
      steps = steps + 1
    }
    if !ok {
      push(
        out,
        row.line,
        Error,
        "CYCLE",
        "HEAD chain from token \{row.start} never reaches a root",
      )
    }
  }
  out
}

///|
fn validate_deps(out : Array[Diagnostic], row : Token, n : Int32) -> Unit {
  if row.deps == "_" {
    if row.kind is Empty {
      push(
        out,
        row.line,
        Error,
        "DEPS_MISSING",
        "empty node must carry a DEPS relation",
      )
    }
    return
  }
  for item in row.deps.split("|") {
    match item.split_once(":") {
      Some((head_raw, rel)) => {
        match parse_deps_head(head_raw) {
          Some(h) =>
            if h < 0 || h > n {
              push(
                out,
                row.line,
                Error,
                "DEPS_RANGE",
                "DEPS head \{h} is outside 0..\{n}",
              )
            }
          None =>
            push(
              out,
              row.line,
              Error,
              "DEPS_FORMAT",
              "DEPS head \{head_raw.to_owned()} is not numeric",
            )
        }
        if !is_valid_enhanced_deprel(rel.to_owned()) {
          push(
            out,
            row.line,
            Error,
            "DEPS_DEPREL",
            "DEPS relation \{rel.to_owned()} is not a known DEPREL",
          )
        }
      }
      None =>
        push(
          out,
          row.line,
          Error,
          "DEPS_FORMAT",
          "DEPS entry \{item.to_owned()} is not head:relation",
        )
    }
  }
}

///|
/// Parses a DEPS head, which may be a plain word index or a decimal empty-node
/// index such as `5.1`.
fn parse_deps_head(s : StringView) -> Int32? {
  if s.is_empty() {
    return None
  }
  let mut acc = 0
  let mut i = 0
  let len = s.length()
  while i < len {
    match s.get_char(i) {
      Some(c) =>
        if c.is_ascii_digit() {
          acc = acc * 10 + c.to_int() - 48
        } else if c == '.' && i > 0 {
          // An empty node `i.k` points at word i; the decimal part is a
          // sub-identifier, not a separate head.
          return Some(acc)
        } else {
          return None
        }
      None => return None
    }
    i = i + 1
  }
  Some(acc)
}

///|
/// Validates every sentence of a document.
pub fn validate(sentences : Array[Sentence]) -> Array[Diagnostic] {
  let out : Array[Diagnostic] = []
  for s in sentences {
    for d in validate_sentence(s) {
      out.push(d)
    }
  }
  out
}

///|
pub fn count_errors(diagnostics : Array[Diagnostic]) -> Int32 {
  let mut n = 0
  for d in diagnostics {
    if d.severity is Error {
      n = n + 1
    }
  }
  n
}
