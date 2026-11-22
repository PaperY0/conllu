///|
/// Checks the properties that only make sense across sentences: every sentence
/// carrying a `# sent_id`, no repeated `# sent_id`, and no document or paragraph
/// id reused inside the same scope. Sentence-level structure is already covered
/// by `validate_sentence`; these findings are about the file as a corpus.
pub fn validate_documents(sentences : Array[Sentence]) -> Array[Diagnostic] {
  let out : Array[Diagnostic] = []
  let sent_ids : Array[String] = []
  let doc_ids : Array[String] = []
  let par_scopes : Array[Int32] = []
  let par_ids : Array[String] = []
  let mut doc_index : Int32 = -1
  for sentence in sentences {
    if sentence.has_newdoc() {
      doc_index = doc_index + 1
      match sentence.newdoc_id() {
        Some(id) =>
          if doc_ids.contains(id) {
            push(
              out,
              sentence.line,
              Warning,
              "NEWDOC_ID_DUPLICATE",
              "document id \{id} is used by more than one # newdoc",
            )
          } else {
            doc_ids.push(id)
          }
        None => ()
      }
    }
    let scope = if doc_index < 0 { 0 } else { doc_index }
    if sentence.has_newpar() {
      if doc_index < 0 {
        push(
          out,
          sentence.line,
          Warning,
          "NEWPAR_WITHOUT_DOC",
          "# newpar appears before any # newdoc",
        )
      }
      match sentence.newpar_id() {
        Some(id) => {
          let mut seen = false
          let mut i = 0
          while i < par_ids.length() {
            if par_scopes.at(i) == scope && par_ids.at(i) == id {
              seen = true
            }
            i = i + 1
          }
          if seen {
            push(
              out,
              sentence.line,
              Warning,
              "NEWPAR_ID_DUPLICATE",
              "paragraph id \{id} is reused inside document \{scope}",
            )
          } else {
            par_scopes.push(scope)
            par_ids.push(id)
          }
        }
        None => ()
      }
    }
    match sentence.comment_value("sent_id") {
      Some(id) =>
        if sent_ids.contains(id) {
          push(
            out,
            sentence.line,
            Error,
            "SENT_ID_DUPLICATE",
            "sent_id \{id} is used by more than one sentence",
          )
        } else {
          sent_ids.push(id)
        }
      None =>
        push(
          out,
          sentence.line,
          Warning,
          "SENT_ID_MISSING",
          "sentence has no # sent_id comment",
        )
    }
  }
  out
}
