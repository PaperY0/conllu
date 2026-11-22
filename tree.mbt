///|
/// Direct children of a word (by 1-based index); the root's children are
/// returned for `head == 0`.
pub fn children(sentence : Sentence, head : Int32) -> Array[Int32] {
  let out : Array[Int32] = []
  for row in sentence.words() {
    match row.head() {
      Some(h) => if h == head { out.push(row.start) }
      None => ()
    }
  }
  out
}

///|
/// All words whose HEAD chain passes through `ancestor`.
pub fn descendants(sentence : Sentence, ancestor : Int32) -> Array[Int32] {
  let out : Array[Int32] = []
  for row in sentence.words() {
    if row.start == ancestor {
      continue
    }
    if is_ancestor(sentence, ancestor, row.start) {
      out.push(row.start)
    }
  }
  out
}

///|
/// True when following HEAD links from `node` reaches `ancestor`.
pub fn is_ancestor(sentence : Sentence, ancestor : Int32, node : Int32) -> Bool {
  let n = sentence.word_count()
  let mut cur = node
  let mut steps : Int32 = 0
  while steps <= n {
    match sentence.word(cur) {
      Some(row) =>
        match row.head() {
          Some(h) =>
            if h == ancestor {
              return true
            } else if h == 0 || h == cur {
              return false
            } else {
              cur = h
            }
          None => return false
        }
      None => return false
    }
    steps = steps + 1
  }
  false
}

///|
/// Depth of a word in its tree: root children have depth 1.
pub fn depth(sentence : Sentence, index : Int32) -> Int32 {
  let n = sentence.word_count()
  let mut cur = index
  let mut d : Int32 = 0
  let mut steps : Int32 = 0
  while steps <= n {
    match sentence.word(cur) {
      Some(row) =>
        match row.head() {
          Some(0) => return d + 1
          Some(h) =>
            if h == cur {
              return d
            } else {
              cur = h
              d = d + 1
            }
          None => return d
        }
      None => return d
    }
    steps = steps + 1
  }
  d
}

///|
/// Longest root-to-leaf distance in the sentence.
pub fn max_depth(sentence : Sentence) -> Int32 {
  let mut best : Int32 = 0
  for row in sentence.words() {
    let d = depth(sentence, row.start)
    if d > best {
      best = d
    }
  }
  best
}

///|
/// A sentence is projective when no two dependency arcs cross. An arc
/// `head -> dep` is projective iff every word strictly between them is a
/// descendant of `head`.
pub fn is_projective(sentence : Sentence) -> Bool {
  let mut ok = true
  for row in sentence.words() {
    match row.head() {
      Some(h) =>
        if h != 0 {
          let lo = if h < row.start { h } else { row.start }
          let hi = if h < row.start { row.start } else { h }
          let mut k = lo + 1
          while k < hi {
            if !is_ancestor(sentence, h, k) {
              ok = false
            }
            k = k + 1
          }
        }
      None => ()
    }
  }
  ok
}

///|
/// Root words of a sentence (HEAD == 0).
pub fn roots(sentence : Sentence) -> Array[Int32] {
  children(sentence, 0)
}
