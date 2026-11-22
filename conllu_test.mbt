///|
let simple : String = "# sent_id = 1\n# text = I saw the cat\n1\tI\tI\tPRON\tPRP\t_\t2\tnsubj\t_\t_\n2\tsaw\tsee\tVERB\tVBD\tTense=Past\t0\troot\t_\t_\n3\tthe\tthe\tDET\tDT\t_\t4\tdet\t_\t_\n4\tcat\tcat\tNOUN\tNN\tNumber=Sing\t2\tobj\t_\tSpaceAfter=No\n5\t.\t.\tPUNCT\t.\t_\t2\tpunct\t_\t_\n"

///|
let complex : String = "# newdoc id = test\n# sent_id = 1\n1-2\tcan't\t_\t_\t_\t_\t_\t_\t_\t_\n1\tca\tcan\tAUX\tMD\t_\t3\taux\t_\t_\n2\tn't\tnot\tPART\tRB\t_\t3\tadvmod\t_\t_\n3\tgo\tgo\tVERB\tVB\t_\t0\troot\t_\t_\n3.1\tgoes\tgo\tVERB\tVBZ\t_\t_\t_\t3:conj\t_\n\n# sent_id = 2\n1\tHi\tHi\tINTJ\tUH\t_\t0\troot\t_\tSpaceAfter=No\n"

///|
test "parse: word rows and comments" {
  let sentences = @conllu.parse(simple)
  assert_eq(sentences.length(), 1)
  let s = sentences[0]
  assert_eq(s.comments().length(), 2)
  assert_eq(s.word_count(), 5)
  let root = s.word(2).unwrap()
  assert_eq(root.head().unwrap(), 0)
  assert_eq(root.deprel, "root")
  assert_eq(root.form, "saw")
  let cat = s.word(4).unwrap()
  assert_eq(cat.head().unwrap(), 2)
  assert_eq(cat.misc, "SpaceAfter=No")
}

///|
test "parse: multiword rows and empty nodes" {
  let sentences = @conllu.parse(complex)
  assert_eq(sentences.length(), 2)
  let s = sentences[0]
  assert_eq(s.word_count(), 3)
  let mut multiwords = 0
  let mut empties = 0
  for row in s.rows() {
    if row.is_multiword() {
      multiwords = multiwords + 1
    }
    if row.is_empty_node() {
      empties = empties + 1
    }
  }
  assert_eq(multiwords, 1)
  assert_eq(empties, 1)
  assert_eq(s.word(1).unwrap().form, "ca")
}

///|
test "serialize: round-trip is byte-identical" {
  let sentences = @conllu.parse(complex)
  let text = @conllu.to_string(sentences)
  assert_eq(text, complex + "\n")
}

///|
test "parse: CRLF input" {
  let crlf = "1\tI\tI\tPRON\tPRP\t_\t0\troot\t_\t_\r\n"
  let sentences = @conllu.parse(crlf)
  assert_eq(sentences.length(), 1)
  assert_eq(sentences[0].word_count(), 1)
  assert_eq(sentences[0].word(1).unwrap().misc, "_")
}

///|
test "validate: clean sentence has no errors" {
  let sentences = @conllu.parse(simple)
  let diagnostics = @conllu.validate(sentences)
  assert_eq(@conllu.count_errors(diagnostics), 0)
}

///|
test "validate: broken ids and root count are reported" {
  let broken : String = "1\ta\ta\tNOUN\tNN\t_\t0\troot\t_\t_\n1\tb\tb\tNOUN\tNN\t_\t1\tdep\t_\t_\n2\tc\tc\tNOUN\tNN\t_\t0\troot\t_\t_\n"
  let sentences = @conllu.parse(broken)
  let diagnostics = @conllu.validate(sentences)
  let codes : Array[String] = []
  for d in diagnostics {
    codes.push(d.code)
  }
  assert_true(codes.contains("ID_SEQUENCE"))
  assert_true(codes.contains("ROOT_COUNT"))
}

///|
test "validate: self loop detected" {
  let broken : String = "1\ta\ta\tNOUN\tNN\t_\t1\troot\t_\t_\n"
  let sentences = @conllu.parse(broken)
  let diagnostics = @conllu.validate(sentences)
  assert_true(@conllu.count_errors(diagnostics) > 0)
}

///|
test "evaluate: identical parses score 100" {
  let gold = @conllu.parse(simple)
  let pred = @conllu.parse(simple)
  let result = @conllu.evaluate(gold, pred)
  assert_eq(result.aligned_tokens, 5)
  assert_eq(result.uas_correct, 5)
  assert_eq(result.las_correct, 5)
  assert_eq(result.uas(), 100.0)
  assert_eq(result.las(), 100.0)
}

///|
test "evaluate: one wrong head lowers both scores" {
  let wrong : String = "# sent_id = 1\n# text = I saw the cat\n1\tI\tI\tPRON\tPRP\t_\t2\tnsubj\t_\t_\n2\tsaw\tsee\tVERB\tVBD\tTense=Past\t0\troot\t_\t_\n3\tthe\tthe\tDET\tDT\t_\t4\tdet\t_\t_\n4\tcat\tcat\tNOUN\tNN\tNumber=Sing\t1\tobj\t_\tSpaceAfter=No\n5\t.\t.\tPUNCT\t.\t_\t2\tpunct\t_\t_\n"
  let gold = @conllu.parse(simple)
  let pred = @conllu.parse(wrong)
  let result = @conllu.evaluate(gold, pred)
  assert_eq(result.aligned_tokens, 5)
  assert_eq(result.uas_correct, 4)
  assert_eq(result.las_correct, 4)
}

///|
test "tree: children, depth and projectivity" {
  let sentences = @conllu.parse(simple)
  let s = sentences[0]
  assert_eq(@conllu.children(s, 2).length(), 3)
  assert_eq(@conllu.depth(s, 2), 1)
  assert_eq(@conllu.depth(s, 4), 2)
  assert_true(@conllu.is_projective(s))
  let crossing : String = "1\ta\ta\tNOUN\tNN\t_\t3\tdep\t_\t_\n2\tb\tb\tNOUN\tNN\t_\t4\tdep\t_\t_\n3\tc\tc\tNOUN\tNN\t_\t0\troot\t_\t_\n4\td\td\tNOUN\tNN\t_\t0\troot\t_\t_\n"
  let cs = @conllu.parse(crossing)
  assert_false(@conllu.is_projective(cs[0]))
}

///|
test "eval: uuas tolerates a reversed direction" {
  let gold : String = "1\ta\ta\tNOUN\tNN\t_\t2\tnsubj\t_\t_\n2\tb\tb\tVERB\tVB\t_\t0\troot\t_\t_\n"
  let pred : String = "1\ta\ta\tNOUN\tNN\t_\t0\troot\t_\t_\n2\tb\tb\tVERB\tVB\t_\t1\tnsubj\t_\t_\n"
  let g = @conllu.parse(gold)
  let p = @conllu.parse(pred)
  let result = @conllu.evaluate(g, p)
  assert_eq(result.uas(), 0.0)
  assert_eq(result.las(), 0.0)
  assert_eq(result.uuas(), 50.0)
}

///|
test "eval: label-wise accuracy ranks the worst relation first" {
  let gold : String = "1\ta\ta\tNOUN\tNN\t_\t2\tnsubj\t_\t_\n2\tb\tb\tVERB\tVB\t_\t0\troot\t_\t_\n3\tc\tc\tNOUN\tNN\t_\t2\tobj\t_\t_\n"
  let pred : String = "1\ta\ta\tNOUN\tNN\t_\t2\tobj\t_\t_\n2\tb\tb\tVERB\tVB\t_\t0\troot\t_\t_\n3\tc\tc\tNOUN\tNN\t_\t2\tobj\t_\t_\n"
  let g = @conllu.parse(gold)
  let p = @conllu.parse(pred)
  let scores = @conllu.evaluate_by_label(g, p)
  assert_eq(scores.length(), 3)
  assert_eq(scores[0].label, "nsubj")
  assert_eq(scores[0].gold, 1)
  assert_eq(scores[0].correct, 0)
  assert_eq(scores[0].las(), 0.0)
  assert_eq(scores[1].label, "obj")
  assert_eq(scores[1].las(), 100.0)
  assert_eq(scores[2].label, "root")
}

///|
test "stats: counts rows by kind" {
  let sentences = @conllu.parse(complex)
  let st = @conllu.stats(sentences)
  assert_eq(st.sentences, 2)
  assert_eq(st.words, 4)
  assert_eq(st.multiwords, 1)
  assert_eq(st.empty_nodes, 1)
  assert_eq(st.max_length, 3)
}

///|
test "validate: enhanced DEPS accept ref and empty-node heads" {
  // `who` carries an enhanced `ref` relation toward the empty node 5.1,
  // exactly the shape UD treebanks use for relative clauses.
  let enhanced : String = "1\twho\twho\tPRON\tWP\t_\t4\tnsubj\t4:nsubj|5.1:ref\t_\n2\tsaw\tsaw\tVERB\tVBD\t_\t0\troot\t0:root\t_\n3\tthe\tthe\tDET\tDT\t_\t4\tdet\t4:det\t_\n4\tcat\tcat\tNOUN\tNN\t_\t2\tobj\t2:obj\t_\n5\tate\teat\tVERB\tVBD\t_\t4\tacl:relcl\t4:acl:relcl\t_\n5.1\tate\teat\tVERB\tVBD\t_\t_\t_\t2:xcomp\t_\n"
  let sentences = @conllu.parse(enhanced)
  let diagnostics = @conllu.validate(sentences)
  assert_eq(@conllu.count_errors(diagnostics), 0)
}
