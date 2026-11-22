///|
/// CoNLL-U row kind. A sentence mixes word rows, multiword-token rows (`1-2`)
/// and empty-node rows (`5.1`).
pub(all) enum RowKind {
  Word
  Multiword
  Empty
}

///|
/// One physical row of a CoNLL-U sentence: the ten tab-separated columns plus
/// positional information derived by the parser.
pub struct Token {
  id_raw : String
  form : String
  lemma : String
  upos : String
  xpos : String
  feats : String
  head_raw : String
  deprel : String
  deps : String
  misc : String
  kind : RowKind
  /// First ID of the row: the word index (1-based) for a word row, the first
  /// covered word for a multiword row, the integer part of the decimal ID for
  /// an empty node.
  start : Int32
  /// Last ID of a multiword row; equal to `start` otherwise.
  end : Int32
  /// 1-based source line number, for diagnostics.
  line : Int32
}

///|
pub fn Token::is_word(self : Token) -> Bool {
  self.kind is Word
}

///|
pub fn Token::is_multiword(self : Token) -> Bool {
  self.kind is Multiword
}

///|
pub fn Token::is_empty_node(self : Token) -> Bool {
  self.kind is Empty
}

///|
/// The HEAD column as an integer, or `None` when the column is `_` (legal only
/// for empty nodes).
pub fn Token::head(self : Token) -> Int32? {
  parse_uint(self.head_raw)
}

///|
/// Number of columns a well-formed CoNLL-U row must have.
let column_count : Int32 = 10

///|
/// One CoNLL-U sentence: the comment block that precedes it and its rows in
/// file order.
pub struct Sentence {
  comments : Array[String]
  rows : Array[Token]
  line : Int32
}

///|
pub fn Sentence::comments(self : Sentence) -> Array[String] {
  self.comments
}

///|
pub fn Sentence::rows(self : Sentence) -> Array[Token] {
  self.rows
}

///|
/// The word rows of a sentence, in ID order.
pub fn Sentence::words(self : Sentence) -> Array[Token] {
  let out : Array[Token] = []
  for row in self.rows {
    if row.kind is Word {
      out.push(row)
    }
  }
  out
}

///|
pub fn Sentence::word_count(self : Sentence) -> Int32 {
  let mut n = 0
  for row in self.rows {
    if row.kind is Word {
      n = n + 1
    }
  }
  n
}

///|
/// 1-based lookup of a word row; `None` when out of range or not a word row.
pub fn Sentence::word(self : Sentence, index : Int32) -> Token? {
  for row in self.rows {
    if row.kind is Word && row.start == index {
      return Some(row)
    }
  }
  None
}

///|
pub fn Sentence::comment(self : Sentence, key : StringView) -> String? {
  for c in self.comments {
    if c.has_prefix(key) {
      return Some(c)
    }
  }
  None
}

///|
/// Raised when the input is not well-formed at the lexical level (wrong column
/// count, unparsable ID, ...). Structural problems are reported by `validate`
/// so that a broken tree can still be inspected.
pub(all) suberror ConlluError {
  ConlluError(Int32, String)
}

///|
/// One enhanced dependency of a word: the head exactly as written in the DEPS
/// column (a word index or an empty-node index such as `5.1`) and its relation.
pub struct EnhancedDep {
  head : String
  rel : String
}

///|
pub fn EnhancedDep::head(self : EnhancedDep) -> String {
  self.head
}

///|
pub fn EnhancedDep::rel(self : EnhancedDep) -> String {
  self.rel
}

///|
pub fn EnhancedDep::to_string(self : EnhancedDep) -> String {
  "\{self.head}:\{self.rel}"
}

///|
/// Structured form of the DEPS column: `1:nsubj|5.1:ref` becomes two entries,
/// with the head kept as a string so an empty-node reference is not flattened
/// into a plain word index. Returns an empty array for `_`.
pub fn Token::enhanced_deps(self : Token) -> Array[EnhancedDep] {
  let out : Array[EnhancedDep] = []
  if self.deps == "_" || self.deps.is_empty() {
    return out
  }
  for item in self.deps.split("|") {
    match item.split_once(":") {
      Some((head_raw, rel)) =>
        out.push({ head: head_raw.to_owned(), rel: rel.to_owned(), })
      None => ()
    }
  }
  out
}

///|
/// The 1-based source line a `ConlluError` points at.
pub fn ConlluError::line(self : ConlluError) -> Int32 {
  match self {
    ConlluError(line, _) => line
  }
}

///|
pub fn ConlluError::message(self : ConlluError) -> String {
  match self {
    ConlluError(_, message) => message
  }
}

///|
fn parse_uint(s : StringView) -> Int32? {
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
fn classify_id(
  id_raw : String,
  line : Int32,
) -> (RowKind, Int32, Int32) raise ConlluError {
  if id_raw.contains("-") {
    let pair = id_raw.split_once("-")
    match pair {
      Some((lhs, rhs)) => {
        let a = parse_uint(lhs)
        let b = parse_uint(rhs)
        match (a, b) {
          (Some(x), Some(y)) => {
            if x <= 0 || y < x {
              raise ConlluError(
                line,
                "multiword ID \{id_raw} is not a valid range",
              )
            }
            (Multiword, x, y)
          }
          _ => raise ConlluError(line, "multiword ID \{id_raw} is not numeric")
        }
      }
      None => raise ConlluError(line, "multiword ID \{id_raw} is malformed")
    }
  } else if id_raw.contains(".") {
    match id_raw.split_once(".") {
      Some((lhs, rhs)) =>
        match (parse_uint(lhs), parse_uint(rhs)) {
          (Some(x), Some(y)) => (Empty, x, y)
          _ => raise ConlluError(line, "empty-node ID \{id_raw} is not numeric")
        }
      None => raise ConlluError(line, "empty-node ID \{id_raw} is malformed")
    }
  } else {
    match parse_uint(id_raw) {
      Some(x) => {
        if x <= 0 {
          raise ConlluError(line, "word ID must be positive, got \{id_raw}")
        }
        (Word, x, x)
      }
      None => raise ConlluError(line, "word ID \{id_raw} is not an integer")
    }
  }
}

///|
fn parse_row(line : String, line_no : Int32) -> Token raise ConlluError {
  let fields = line.split("\t").to_array()
  if fields.length() != column_count {
    raise ConlluError(
      line_no,
      "expected \{column_count} tab-separated columns, got \{fields.length()}",
    )
  }
  let id_raw = fields[0].to_owned()
  let (kind, start, end) = classify_id(id_raw, line_no)
  {
    id_raw,
    form: fields[1].to_owned(),
    lemma: fields[2].to_owned(),
    upos: fields[3].to_owned(),
    xpos: fields[4].to_owned(),
    feats: fields[5].to_owned(),
    head_raw: fields[6].to_owned(),
    deprel: fields[7].to_owned(),
    deps: fields[8].to_owned(),
    misc: fields[9].to_owned(),
    kind,
    start,
    end,
    line: line_no,
  }
}

///|
/// Parses a complete CoNLL-U document. Blank lines separate sentences; a
/// leading comment block belongs to the sentence that follows it.
pub fn parse(text : String) -> Array[Sentence] raise ConlluError {
  let sentences : Array[Sentence] = []
  let mut comments : Array[String] = []
  let mut rows : Array[Token] = []
  let mut start_line : Int32 = 1
  let mut line_no : Int32 = 0
  for raw in text.split("\n") {
    line_no = line_no + 1
    let line = match raw.strip_suffix("\r") {
      Some(v) => v.to_owned()
      None => raw.to_owned()
    }
    if line.is_empty() {
      if rows.length() > 0 || comments.length() > 0 {
        sentences.push({ comments, rows, line: start_line, })
        comments = []
        rows = []
      }
      start_line = line_no + 1
      continue
    }
    if line.has_prefix("#") {
      if rows.length() == 0 && comments.length() == 0 {
        start_line = line_no
      }
      comments.push(line)
      continue
    }
    if rows.length() == 0 && comments.length() == 0 {
      start_line = line_no
    }
    rows.push(parse_row(line, line_no))
  }
  if rows.length() > 0 || comments.length() > 0 {
    sentences.push({ comments, rows, line: start_line, })
  }
  sentences
}

///|
fn write_row(sb : StringBuilder, row : Token) -> Unit {
  sb.write_string(row.id_raw)
  sb.write_string("\t")
  sb.write_string(row.form)
  sb.write_string("\t")
  sb.write_string(row.lemma)
  sb.write_string("\t")
  sb.write_string(row.upos)
  sb.write_string("\t")
  sb.write_string(row.xpos)
  sb.write_string("\t")
  sb.write_string(row.feats)
  sb.write_string("\t")
  sb.write_string(row.head_raw)
  sb.write_string("\t")
  sb.write_string(row.deprel)
  sb.write_string("\t")
  sb.write_string(row.deps)
  sb.write_string("\t")
  sb.write_string(row.misc)
}

///|
/// Serialises one sentence back to CoNLL-U, without the trailing blank line.
pub fn Sentence::to_string(self : Sentence) -> String {
  let sb = StringBuilder::StringBuilder()
  for c in self.comments {
    sb.write_string(c)
    sb.write_string("\n")
  }
  for row in self.rows {
    write_row(sb, row)
    sb.write_string("\n")
  }
  sb.to_string()
}

///|
/// Serialises a document with one blank line between sentences.
pub fn to_string(sentences : Array[Sentence]) -> String {
  let sb = StringBuilder::StringBuilder()
  for s in sentences {
    sb.write_string(s.to_string())
    sb.write_string("\n")
  }
  sb.to_string()
}

///|
/// Formats a single row back to one line.
pub fn Token::to_line(self : Token) -> String {
  let sb = StringBuilder::StringBuilder()
  write_row(sb, self)
  sb.to_string()
}
