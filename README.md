# cl-lucene

A native Common Lisp API for [Apache Lucene](https://lucene.apache.org/),
running on [OpenLDK](https://github.com/atgreen/openldk).

Lucene is a Java library, but with OpenLDK it runs inside SBCL in the same
process and heap as your Lisp code — no JVM subprocess, no sockets, no
serialization. `cl-lucene` wraps it in an idiomatic Lisp API: you build an
index and search it with Lisp data, and never see a Java method descriptor.

```lisp
(ql:quickload :cl-lucene)   ; or (asdf:load-system "cl-lucene")

;; Build an on-disk index.
(lucene:with-writer (w #p"/tmp/books/" :if-exists :create)
  (lucene:add-document w '(("title" "The Lisp Machine")
                           ("body"  "a quick brown fox of symbolic computation")
                           ("id"    "1"  :type :string)
                           ("year"  1985 :type :int)))
  (lucene:add-document w '(("title" "The Quick Fox Cookbook")
                           ("body"  "quick brown fox jumps over the lazy dog")
                           ("id"    "2"  :type :string)
                           ("year"  2001 :type :int))))

;; Search it.
(lucene:with-searcher (s #p"/tmp/books/" :default-field "body")
  (lucene:search-count s "quick fox")                ; => 2
  (dolist (hit (lucene:search s "quick fox" :limit 10))
    (format t "~A (~A) score ~,3F~%"
            (lucene:hit-field hit "title")
            (lucene:hit-field hit "year")
            (lucene:hit-score hit))))
```

## Requirements

- SBCL on Linux
- OpenLDK, loadable as the ASDF system `openldk/interop`
- A JDK 25 (OpenLDK reads its classes), with `JAVA_HOME` set
- Network access on first use, to fetch the Lucene jars from Maven Central
  into OpenLDK's cache (`~/.cache/openldk/`); offline afterwards

The Lucene jars (`lucene-core`, `lucene-analysis-common`, `lucene-queryparser`,
`lucene-queries`, `lucene-memory`, `lucene-facet`, `lucene-highlighter`,
`lucene-suggest`, `lucene-grouping`, `lucene-join`) are downloaded automatically
the first time the runtime starts. The version is `lucene:*lucene-version*`
(10.6.0 by default).

## API

### Directories

- `(open-directory path)` — open, creating if needed, an on-disk index at
  `path` (a pathname or namestring, memory-mapped where the platform allows),
  or pass `:memory` for an in-memory directory. Close it with `close`.

### Writing

- `(with-writer (var target &key analyzer if-exists) &body body)` — open a
  writer on `target` (a directory, a path, or `:memory`) for the body, then
  close it. A path or `:memory` is opened into a directory closed with the
  writer.
- `(make-writer directory &key analyzer if-exists)` — the explicit form.
  `if-exists` is `:create`, `:append`, or `:create-or-append` (default).
- `(add-document writer fields)` — add a document. `fields` is a list of
  specs, each `(name value &key type store)`:
  - `:text` — analyzed full-text, searched word by word (the default)
  - `:string` — an exact, un-analyzed value (an id, a tag); also sortable and
    facetable (a `KeywordField`, with doc-values)
  - `:stored` — stored but not indexed
  - `:int` `:long` `:float` `:double` — a number, indexed for range and sort
  - `:vector` — a dense float vector for k-NN search; `value` is a sequence of
    reals and `:similarity` is `:euclidean` (default), `:cosine`,
    `:dot-product`, or `:max-inner-product`
  - `:facet` — a facet value (`name` is the dimension, `value` its label),
    counted by `facets`
  - `:geo` — a geographic point (`value` is `(latitude longitude)`)
  - `:sorted-string` — a single-valued string (doc-values only) to group on
  - `store` (default `t`) keeps the value so a hit can read it back
- `(commit writer)` — flush changes so searchers can see them.
- `(delete-documents writer target)` — delete by a query, or by a term given as
  `(field value)`.
- `(update-document writer field value fields)` — atomically replace the
  document whose `field` holds exactly `value` with a new one.
- `(delete-all writer)` — empty the index.

### Searching

- `(with-searcher (var target &key analyzer default-field) &body body)` — open
  a searcher for the body, then close it.
- `(make-searcher directory &key analyzer default-field)` — the explicit form.
  A searcher sees a point-in-time view; reopen to see later commits.
- `(search searcher query &key (limit 10) sort after highlight)` — search for
  `query` (a query string parsed by Lucene's classic QueryParser over
  `default-field`, or a `Query` object from the builders below). Returns two
  values: up to `limit` `hit`s, and the total number of matches. Without `sort`,
  hits come most-relevant first; `sort` is a key or list of keys — `:score`,
  `:doc`, or `(field type &optional direction)` where `type` is
  `:int`/`:long`/`:float`/`:double`/`:string` and `direction` is `:asc`
  (default) or `:desc`. `after` is a `hit` from the previous page (its last
  one), for paging beyond `limit`. `highlight` is a field name whose matched
  text is highlighted into each hit's `hit-snippet`.
- `(search-count searcher query)` — how many documents match, without fetching.
- `(facets searcher query dims &key (top 10))` — count the matches by their
  `:facet` values; `dims` is a list of facet field names. Returns an alist
  mapping each dimension to a list of `(label . count)`, most frequent first.
- `(explain searcher query hit-or-id)` — a human-readable explanation of how
  `query` scored a document (plus the Lucene `Explanation` as a second value).
- `(group-search searcher query group-field &key (limit 10) (hits-per-group 1))`
  — collapse results into groups sharing a `:sorted-string` field value;
  returns a list of `group`s (`group-value`, `group-hits`, `group-total`).
- A `hit` has `hit-score`, `hit-id`, `hit-fields` (an alist), `hit-snippet`, and
  `(hit-field hit name)` for one stored field's value.

### Nested documents (block join)

- `(add-block writer parent children)` — index a parent and its child documents
  (each a field-spec list) as one block; give the parent a marker field.
- `(block-join-query child-query parent-query &key (score :avg))` — match parent
  documents that have a child matching `child-query`; `parent-query` identifies
  the parents.

### Autocomplete

- `(make-suggester &key analyzer)` → a suggester; `(suggest-add s text :weight w)`,
  `(suggest-commit s)`, then `(suggest s prefix &key (limit 10))` →
  `(text . weight)` completions, best first. `close` it when done.

### Query parsers

Richer than the default classic parse `make-searcher` does for a string:

- `(query-parser field &key analyzer default-operator allow-leading-wildcard
  phrase-slop fuzzy-min-sim)` — a configured classic parser
  (`default-operator` is `:or` or `:and`)
- `(simple-query-parser fields &key analyzer)` — a forgiving parser that never
  throws; `fields` is a name, a list of names, or `(name . weight)` conses
- `(multi-field-query-parser fields &key analyzer)` — classic parse across
  several fields
- `(parse parser string)` — turn a string into a `Query` with any of the above

### Query builders

As an alternative to query strings, these build `Query` objects to pass to
`search`/`search-count`:

- `(match-all-query)`
- `(term-query field value)` — exact term
- `(phrase-query field terms &key (slop 0))` — a phrase, `slop` positions apart
- `(prefix-query field prefix)`, `(wildcard-query field pattern)` (`?`/`*`),
  `(fuzzy-query field value)`, `(regexp-query field pattern)`
- `(range-query field &key min max (type :int) include-min include-max)` —
  numeric ranges (`:int`/`:long`/`:float`/`:double`, inclusive, open ends
  allowed) or lexicographic term ranges (`:text`/`:string`, with inclusive/
  exclusive ends)
- `(boolean-query &key must should must-not filter min-should-match)` — combine
  queries; each keyword takes one query or a list
- `(boost-query query boost)` — multiply a query's scores by `boost`
- `(knn-query field vector &key (k 10) filter)` — the `k` documents whose
  `:vector` field is nearest to `vector`, optionally restricted by `filter`
- `(near-query field terms &key (max-gaps 0) (ordered t))` — proximity: the
  terms within `max-gaps` positions (`0` = adjacent phrase), in order or not
- `(geo-distance-query field lat lon radius-meters)`,
  `(geo-box-query field min-lat max-lat min-lon max-lon)` — search `:geo` points

### Analyzers

`make-analyzer` and the `:analyzer` keywords take `:standard` (the default),
`:keyword`, `:whitespace`, `:simple`, `:english`, or an Analyzer object. Two
builders make custom analyzers (also usable anywhere an `:analyzer` is):

- `(custom-analyzer &key tokenizer char-filters token-filters)` — compose a
  tokenizer and filter chain by Lucene SPI name, e.g.
  `(custom-analyzer :tokenizer "standard" :token-filters '(("lowercase") ("porterStem")))`
- `(per-field-analyzer default field analyzer field analyzer …)` — route
  different fields to different analyzers

## Status

Broad. Working and covered by tests (`asdf:test-system "cl-lucene"`, 30 tests):
indexing text, string, stored, numeric, dense-vector, facet, geo and
sorted-string fields; query-string and `Query`-object search; the query
builders (term, phrase, prefix, wildcard, fuzzy, regexp, numeric and term
ranges, boolean, boost, k-NN vector, proximity/`near`, geo distance and box);
the configurable classic, simple and multi-field query parsers; custom and
per-field analyzers; counts, ranked hits, total-hit counts, sorting (numeric
and string), `searchAfter` paging, scoring `explain`, faceting, highlighting,
result grouping, nested/block-join, autocomplete suggestions, and stored-field
retrieval; delete-by-term, delete-by-query, and update-document. Not wrapped
yet: taxonomy/range facets, drill-sideways, function/expression scoring, custom
`Similarity`, and near-real-time `SearcherManager` — straightforward additions
on this foundation.

## License

MIT. See the headers in each source file.
