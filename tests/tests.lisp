;;;; tests/tests.lisp --- cl-lucene test suite.
;;;;
;;;; Copyright (C) 2026  Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: MIT

(defpackage #:cl-lucene/tests
  (:use #:cl #:fiveam)
  (:export #:cl-lucene))

(in-package #:cl-lucene/tests)

(def-suite cl-lucene
  :description "Indexing and searching through the cl-lucene API.")

(in-suite cl-lucene)

(defmacro with-sample-index ((searcher) &body body)
  "Build a small in-memory index of three documents and bind SEARCHER to a
searcher over it (default field \"body\") for BODY."
  (let ((dir (gensym "DIR")) (writer (gensym "W")))
    `(let ((,dir (lucene:open-directory :memory)))
       (unwind-protect
            (progn
              (let ((,writer (lucene:make-writer ,dir :if-exists :create)))
                (lucene:add-document ,writer '(("title" "The Lisp Machine")
                                               ("body" "a quick brown fox of symbolic computation")
                                               ("id" "1" :type :string)
                                               ("year" 1985 :type :int)))
                (lucene:add-document ,writer '(("title" "Structure and Interpretation")
                                               ("body" "the lazy dog sleeps while wizards compute")
                                               ("id" "2" :type :string)
                                               ("year" 1984 :type :int)))
                (lucene:add-document ,writer '(("title" "The Quick Fox Cookbook")
                                               ("body" "quick brown fox jumps over the lazy dog")
                                               ("id" "3" :type :string)
                                               ("year" 2001 :type :int)))
                (lucene:commit ,writer)
                (lucene:close ,writer))
              (let ((,searcher (lucene:make-searcher ,dir :default-field "body")))
                (unwind-protect (progn ,@body)
                  (lucene:close ,searcher))))
         (lucene:close ,dir)))))

(test single-term-count
  "A single-term query counts the documents that contain it."
  (with-sample-index (s)
    (is (= 2 (lucene:search-count s "quick")))
    (is (= 2 (lucene:search-count s "lazy")))
    (is (= 0 (lucene:search-count s "nonexistent")))))

(test multi-term-count
  "A multi-term (BooleanQuery) query -- the shape that exercised the OpenLDK
long->Long boxing path -- counts correctly."
  (with-sample-index (s)
    (is (= 2 (lucene:search-count s "quick fox")))
    (is (= 3 (lucene:search-count s "quick lazy")))))

(test search-returns-ranked-hits
  "SEARCH returns HITs, most relevant first, up to the limit."
  (with-sample-index (s)
    (let ((hits (lucene:search s "quick fox" :limit 10)))
      (is (= 2 (length hits)))
      (is (every #'lucene:hit-p hits))
      (is (apply #'>= (mapcar #'lucene:hit-score hits))))))

(test stored-fields-read-back
  "A hit exposes the document's stored fields, strings and numbers alike."
  (with-sample-index (s)
    (let ((hit (first (lucene:search s "id:1" :limit 1))))
      (is (not (null hit)))
      (is (string= "The Lisp Machine" (lucene:hit-field hit "title")))
      (is (string= "1" (lucene:hit-field hit "id")))
      (is (eql 1985 (lucene:hit-field hit "year"))))))

(test exact-string-field
  "A :string field matches as an exact, un-analyzed term via field:value."
  (with-sample-index (s)
    (is (= 1 (lucene:search-count s "id:2")))
    (is (= 0 (lucene:search-count s "id:99")))))

(test query-object-and-string
  "SEARCH accepts both a query string and a pre-parsed Query object."
  (with-sample-index (s)
    (let ((q (lucene::parse-query s "quick")))
      (is (= (lucene:search-count s "quick")
             (lucene:search-count s q))))))

(test query-builders
  "The programmatic query builders match the documents they should."
  (with-sample-index (s)
    (is (= 3 (lucene:search-count s (lucene:match-all-query))))
    (is (= 2 (lucene:search-count s (lucene:term-query "body" "quick"))))
    (is (= 2 (lucene:search-count s (lucene:phrase-query "body" '("brown" "fox")))))
    (is (= 0 (lucene:search-count s (lucene:phrase-query "body" '("quick" "fox")))))
    (is (= 2 (lucene:search-count s (lucene:phrase-query "body" '("quick" "fox") :slop 2))))
    (is (= 2 (lucene:search-count s (lucene:prefix-query "body" "comput"))))
    (is (= 2 (lucene:search-count s (lucene:wildcard-query "body" "comput*"))))))

(test range-queries
  "Numeric and string range queries select the right documents."
  (with-sample-index (s)
    (is (= 2 (lucene:search-count s (lucene:range-query "year" :type :int :min 1985))))
    (is (= 2 (lucene:search-count s (lucene:range-query "year" :type :int :min 1984 :max 1985))))
    (is (= 1 (lucene:search-count s (lucene:range-query "year" :type :int :max 1984))))
    (is (= 2 (lucene:search-count s (lucene:range-query "id" :type :string :min "1" :max "2"))))))

(test boolean-query
  "BOOLEAN-QUERY combines must / should / must-not clauses."
  (with-sample-index (s)
    (is (= 1 (lucene:search-count
              s (lucene:boolean-query :must (lucene:term-query "body" "quick")
                                        :must-not (lucene:term-query "body" "jumps")))))
    (is (= 3 (lucene:search-count
              s (lucene:boolean-query :should (list (lucene:term-query "body" "quick")
                                                    (lucene:term-query "body" "lazy"))))))))

(test search-returns-total
  "SEARCH returns the total match count as its second value, beyond the limit."
  (with-sample-index (s)
    (multiple-value-bind (hits total) (lucene:search s "quick" :limit 1)
      (is (= 1 (length hits)))
      (is (= 2 total)))))

(test search-with-sort
  "SEARCH sorts hits by a field when :sort is given."
  (with-sample-index (s)
    (let ((hits (lucene:search s (lucene:match-all-query)
                               :sort '("year" :int :desc))))
      (is (= 3 (length hits)))
      (is (eql 2001 (lucene:hit-field (first hits) "year")))
      (is (eql 1984 (lucene:hit-field (car (last hits)) "year"))))))

(test search-with-sort-and-after
  "Paging with :after works together with :sort (the 4-arg searchAfter)."
  (with-sample-index (s)
    (let* ((page1 (lucene:search s (lucene:match-all-query) :sort '("year" :int :desc) :limit 2))
           (page2 (lucene:search s (lucene:match-all-query) :sort '("year" :int :desc) :limit 2
                                   :after (car (last page1)))))
      (is (= 2 (length page1)))
      (is (= 1 (length page2)))
      ;; Descending by year across both pages: 2001, 1985, 1984.
      (is (equal '(2001 1985 1984)
                 (append (mapcar (lambda (h) (lucene:hit-field h "year")) page1)
                         (mapcar (lambda (h) (lucene:hit-field h "year")) page2)))))))

(defmacro with-mutable-index ((dir) &body body)
  "Bind DIR to a fresh in-memory directory holding two documents (ids a and b)
for BODY, then close it.  BODY may open further writers and searchers on DIR."
  `(let ((,dir (lucene:open-directory :memory)))
     (unwind-protect
          (progn
            (let ((w (lucene:make-writer ,dir :if-exists :create)))
              (lucene:add-document w '(("id" "a" :type :string) ("body" "alpha quick")))
              (lucene:add-document w '(("id" "b" :type :string) ("body" "beta quick")))
              (lucene:commit w)
              (lucene:close w))
            ,@body)
       (lucene:close ,dir))))

(test delete-by-term-and-query
  "DELETE-DOCUMENTS removes documents by term and by query."
  (with-mutable-index (dir)
    (let ((w (lucene:make-writer dir)))
      (lucene:delete-documents w '("id" "a"))       ; by term
      (lucene:commit w)
      (lucene:close w))
    (lucene:with-searcher (s dir :default-field "body")
      (is (= 1 (lucene:search-count s (lucene:match-all-query))))
      (is (= 0 (lucene:search-count s "alpha"))))
    (let ((w (lucene:make-writer dir)))
      (lucene:delete-documents w (lucene:term-query "body" "quick"))  ; by query
      (lucene:commit w)
      (lucene:close w))
    (lucene:with-searcher (s dir :default-field "body")
      (is (= 0 (lucene:search-count s (lucene:match-all-query)))))))

(test update-document
  "UPDATE-DOCUMENT replaces a document identified by a key term."
  (with-mutable-index (dir)
    (let ((w (lucene:make-writer dir)))
      (lucene:update-document w "id" "b" '(("id" "b" :type :string) ("body" "beta gamma")))
      (lucene:commit w)
      (lucene:close w))
    (lucene:with-searcher (s dir :default-field "body")
      (is (= 2 (lucene:search-count s (lucene:match-all-query))))
      (is (= 1 (lucene:search-count s "gamma")))
      (is (= 1 (lucene:search-count s "alpha"))))))

;;; Coverage added for the goal: KNN vectors, string-field sort (doc-values),
;;; boosting, regexp, explain, and searchAfter paging.

(test string-field-sort
  "A :string field (KeywordField, with doc-values) can be sorted on."
  (with-sample-index (s)
    (let ((hits (lucene:search s (lucene:match-all-query) :sort '("id" :string :desc))))
      (is (equal '("3" "2" "1")
                 (mapcar (lambda (h) (lucene:hit-field h "id")) hits))))))

(test boost-query-raises-score
  "BOOST-QUERY multiplies a clause's score without changing what matches."
  (with-sample-index (s)
    (is (= 2 (lucene:search-count s (lucene:boost-query (lucene:term-query "body" "fox") 3.0))))
    (let ((plain (lucene:hit-score (first (lucene:search s (lucene:term-query "body" "fox")))))
          (boosted (lucene:hit-score
                    (first (lucene:search s (lucene:boost-query (lucene:term-query "body" "fox") 3.0))))))
      (is (> boosted (* 2.5 plain))))))

(test regexp-query-matches
  "REGEXP-QUERY matches terms against a Lucene regular expression."
  (with-sample-index (s)
    (is (= 2 (lucene:search-count s (lucene:regexp-query "body" "comp.*"))))
    (is (= 1 (lucene:search-count s (lucene:regexp-query "body" "wizard.?"))))))

(test explain-returns-text
  "EXPLAIN returns a human-readable scoring explanation."
  (with-sample-index (s)
    (let ((hit (first (lucene:search s "quick"))))
      (multiple-value-bind (text object) (lucene:explain s "quick" hit)
        (is (not (null object)))
        (is (stringp text))
        (is (plusp (length text)))))))

(test search-after-paging
  "SEARCH's :after cursor pages through results without overlap."
  (with-sample-index (s)
    (let* ((page1 (lucene:search s (lucene:match-all-query) :limit 2))
           (page2 (lucene:search s (lucene:match-all-query) :limit 2 :after (car (last page1)))))
      (is (= 2 (length page1)))
      (is (= 1 (length page2)))
      (let ((ids (append (mapcar (lambda (h) (lucene:hit-field h "id")) page1)
                         (mapcar (lambda (h) (lucene:hit-field h "id")) page2))))
        (is (= 3 (length (remove-duplicates ids :test #'string=))))))))

(defmacro with-vector-index ((searcher) &body body)
  "Bind SEARCHER to a searcher over a three-document in-memory index whose
documents carry a 2-D :vector field (ids x, y, z) for BODY, then close it."
  (let ((dir (gensym "DIR")) (writer (gensym "W")))
    `(let ((,dir (lucene:open-directory :memory)))
       (unwind-protect
            (progn
              (let ((,writer (lucene:make-writer ,dir :if-exists :create)))
                (lucene:add-document ,writer '(("id" "x" :type :string)
                                               ("vec" (1.0 0.0) :type :vector :similarity :euclidean)))
                (lucene:add-document ,writer '(("id" "y" :type :string)
                                               ("vec" (0.0 1.0) :type :vector :similarity :euclidean)))
                (lucene:add-document ,writer '(("id" "z" :type :string)
                                               ("vec" (0.9 0.1) :type :vector :similarity :euclidean)))
                (lucene:commit ,writer)
                (lucene:close ,writer))
              (let ((,searcher (lucene:make-searcher ,dir)))
                (unwind-protect (progn ,@body)
                  (lucene:close ,searcher))))
         (lucene:close ,dir)))))

(test knn-vector-search
  "KNN-QUERY finds the nearest vectors to a query vector."
  (with-vector-index (s)
    (let ((hits (lucene:search s (lucene:knn-query "vec" '(1.0 0.0) :k 2))))
      (is (= 2 (length hits)))
      (is (string= "x" (lucene:hit-field (first hits) "id")))   ; nearest
      (is (string= "z" (lucene:hit-field (second hits) "id")))) ; next nearest
    ;; With a filter, only filtered documents are candidates.
    (let ((hits (lucene:search s (lucene:knn-query "vec" '(1.0 0.0) :k 3
                                                   :filter (lucene:term-query "id" "y")))))
      (is (= 1 (length hits)))
      (is (string= "y" (lucene:hit-field (first hits) "id"))))))

;;; Coverage added for the goal: richer query parsers, analysis building,
;;; faceting, and highlighting.

(test configurable-classic-parser
  "QUERY-PARSER's :default-operator switches between OR and AND semantics."
  (with-sample-index (s)
    (is (= 3 (lucene:search-count
              s (lucene:parse (lucene:query-parser "body" :default-operator :or) "quick lazy"))))
    (is (= 1 (lucene:search-count
              s (lucene:parse (lucene:query-parser "body" :default-operator :and) "quick lazy"))))))

(test simple-and-multi-field-parsers
  "SIMPLE-QUERY-PARSER and MULTI-FIELD-QUERY-PARSER search across fields."
  (with-sample-index (s)
    ;; 'cookbook' appears only in doc 3's title.
    (is (= 1 (lucene:search-count
              s (lucene:parse (lucene:simple-query-parser '("title" "body")) "cookbook"))))
    (is (= 1 (lucene:search-count
              s (lucene:parse (lucene:multi-field-query-parser '("title" "body")) "cookbook"))))
    ;; 'wizards' appears only in doc 2's body.
    (is (= 1 (lucene:search-count
              s (lucene:parse (lucene:simple-query-parser '("title" "body")) "wizards"))))))

(test custom-analyzer-stemming
  "CUSTOM-ANALYZER composes a tokenizer + filters; here Porter stemming makes
'running' match a search for 'run'."
  (let* ((analyzer (lucene:custom-analyzer
                    :tokenizer "standard"
                    :token-filters '(("lowercase") ("porterStem"))))
         (dir (lucene:open-directory :memory)))
    (unwind-protect
         (progn
           (let ((w (lucene:make-writer dir :analyzer analyzer :if-exists :create)))
             (lucene:add-document w '(("body" "the cats were running quickly")))
             (lucene:commit w)
             (lucene:close w))
           (let ((se (lucene:make-searcher dir :analyzer analyzer :default-field "body")))
             (unwind-protect
                  (progn
                    (is (= 1 (lucene:search-count se "run")))   ; running -> run
                    (is (= 1 (lucene:search-count se "cat"))))  ; cats -> cat
               (lucene:close se))))
      (lucene:close dir))))

(test per-field-analyzer-usable
  "PER-FIELD-ANALYZER builds a working analyzer routing fields to sub-analyzers."
  (let* ((analyzer (lucene:per-field-analyzer :standard "tag" :keyword))
         (dir (lucene:open-directory :memory)))
    (unwind-protect
         (progn
           (let ((w (lucene:make-writer dir :analyzer analyzer :if-exists :create)))
             (lucene:add-document w '(("body" "hello world") ("tag" "needs triage")))
             (lucene:commit w)
             (lucene:close w))
           (let ((se (lucene:make-searcher dir :analyzer analyzer :default-field "body")))
             (unwind-protect
                  (is (= 1 (lucene:search-count se "hello")))
               (lucene:close se))))
      (lucene:close dir))))

(defmacro with-faceted-index ((searcher) &body body)
  "Bind SEARCHER to a three-document index with :facet fields category and
author for BODY, then close it."
  (let ((dir (gensym "DIR")) (writer (gensym "W")))
    `(let ((,dir (lucene:open-directory :memory)))
       (unwind-protect
            (progn
              (let ((,writer (lucene:make-writer ,dir :if-exists :create)))
                (lucene:add-document ,writer '(("body" "x")
                                               ("category" "fiction" :type :facet)
                                               ("author" "alice" :type :facet)))
                (lucene:add-document ,writer '(("body" "x")
                                               ("category" "fiction" :type :facet)
                                               ("author" "bob" :type :facet)))
                (lucene:add-document ,writer '(("body" "x")
                                               ("category" "tech" :type :facet)
                                               ("author" "alice" :type :facet)))
                (lucene:commit ,writer)
                (lucene:close ,writer))
              (let ((,searcher (lucene:make-searcher ,dir :default-field "body")))
                (unwind-protect (progn ,@body)
                  (lucene:close ,searcher))))
         (lucene:close ,dir)))))

(test facet-counts
  "FACETS breaks a result set down by facet-field values, most frequent first."
  (with-faceted-index (s)
    (let ((result (lucene:facets s (lucene:match-all-query) '("category" "author"))))
      (is (equal '(("fiction" . 2) ("tech" . 1)) (cdr (assoc "category" result :test #'string=))))
      (is (equal '(("alice" . 2) ("bob" . 1)) (cdr (assoc "author" result :test #'string=)))))))

(test highlighting
  "SEARCH's :highlight fills each hit's SNIPPET with a highlighted fragment."
  (with-sample-index (s)
    (let ((hit (first (lucene:search s "quick" :highlight "body"))))
      (is (not (null (lucene:hit-snippet hit))))
      (is (search "quick" (lucene:hit-snippet hit)))
      (is (search "<b>" (lucene:hit-snippet hit))))))

;;; Coverage added for the goal: proximity (interval) queries, geo queries,
;;; autocomplete suggestions, result grouping, and nested/block-join.

(test near-query-proximity
  "NEAR-QUERY matches terms within a gap, honouring order."
  (with-sample-index (s)
    (is (= 0 (lucene:search-count s (lucene:near-query "body" '("quick" "fox") :max-gaps 0))))
    (is (= 2 (lucene:search-count s (lucene:near-query "body" '("quick" "fox") :max-gaps 1))))
    (is (= 0 (lucene:search-count s (lucene:near-query "body" '("fox" "quick") :max-gaps 5 :ordered t))))
    (is (= 2 (lucene:search-count s (lucene:near-query "body" '("fox" "quick") :max-gaps 5 :ordered nil))))))

(defmacro with-geo-index ((searcher) &body body)
  "Bind SEARCHER to an index of three :geo points (two near New York, one in
Los Angeles) for BODY, then close it."
  (let ((dir (gensym)) (writer (gensym)))
    `(let ((,dir (lucene:open-directory :memory)))
       (unwind-protect
            (progn
              (let ((,writer (lucene:make-writer ,dir :if-exists :create)))
                (lucene:add-document ,writer '(("id" "nyc" :type :string) ("loc" (40.7128 -74.0060) :type :geo)))
                (lucene:add-document ,writer '(("id" "near" :type :string) ("loc" (40.7300 -73.9900) :type :geo)))
                (lucene:add-document ,writer '(("id" "la" :type :string) ("loc" (34.0522 -118.2437) :type :geo)))
                (lucene:commit ,writer)
                (lucene:close ,writer))
              (let ((,searcher (lucene:make-searcher ,dir)))
                (unwind-protect (progn ,@body) (lucene:close ,searcher))))
         (lucene:close ,dir)))))

(test geo-queries
  "Geo distance and box queries select points by location."
  (with-geo-index (s)
    (is (= 2 (lucene:search-count s (lucene:geo-distance-query "loc" 40.71 -74.00 50000.0))))
    (is (= 2 (lucene:search-count s (lucene:geo-box-query "loc" 40.0 41.0 -75.0 -73.0))))
    (is (= 1 (lucene:search-count s (lucene:geo-box-query "loc" 33.0 35.0 -119.0 -117.0))))))

(test autocomplete
  "A suggester returns weighted infix completions, best first."
  (let ((suggester (lucene:make-suggester)))
    (unwind-protect
         (progn
           (lucene:suggest-add suggester "common lisp" :weight 10)
           (lucene:suggest-add suggester "common sense" :weight 5)
           (lucene:suggest-add suggester "uncommon valor" :weight 1)
           (lucene:suggest-commit suggester)
           (let ((results (lucene:suggest suggester "common")))
             (is (= 2 (length results)))
             (is (string= "common lisp" (car (first results))))
             (is (eql 10 (cdr (first results))))))
      (lucene:close suggester))))

(test result-grouping
  "GROUP-SEARCH collapses results into groups by a :sorted-string field."
  (let ((dir (lucene:open-directory :memory)))
    (unwind-protect
         (progn
           (let ((w (lucene:make-writer dir :if-exists :create)))
             (lucene:add-document w '(("body" "x") ("cat" "fiction" :type :sorted-string)))
             (lucene:add-document w '(("body" "x") ("cat" "fiction" :type :sorted-string)))
             (lucene:add-document w '(("body" "x") ("cat" "tech" :type :sorted-string)))
             (lucene:commit w)
             (lucene:close w))
           (let ((se (lucene:make-searcher dir :default-field "body")))
             (unwind-protect
                  (let ((groups (lucene:group-search se (lucene:match-all-query) "cat"
                                                      :limit 10 :hits-per-group 10)))
                    (is (= 2 (length groups)))
                    (is (eql 2 (group-total-for groups "fiction")))
                    (is (eql 1 (group-total-for groups "tech"))))
               (lucene:close se))))
      (lucene:close dir))))

(defun group-total-for (groups value)
  "The TOTAL of the group in GROUPS whose VALUE is VALUE, or NIL."
  (let ((group (find value groups :key #'lucene:group-value :test #'equal)))
    (and group (lucene:group-total group))))

(test nested-block-join
  "ADD-BLOCK indexes parent+children; BLOCK-JOIN-QUERY finds parents by child."
  (let ((dir (lucene:open-directory :memory)))
    (unwind-protect
         (progn
           (let ((w (lucene:make-writer dir :if-exists :create)))
             (lucene:add-block w
                               '(("kind" "book" :type :string) ("title" "Lisp"))
                               (list '(("kind" "chapter" :type :string) ("text" "quick brown fox"))
                                     '(("kind" "chapter" :type :string) ("text" "lazy dog"))))
             (lucene:add-block w
                               '(("kind" "book" :type :string) ("title" "Java"))
                               (list '(("kind" "chapter" :type :string) ("text" "verbose enterprise"))))
             (lucene:commit w)
             (lucene:close w))
           (let ((se (lucene:make-searcher dir :default-field "text")))
             (unwind-protect
                  (let* ((query (lucene:block-join-query (lucene:term-query "text" "fox")
                                                         (lucene:term-query "kind" "book")))
                         (hits (lucene:search se query)))
                    (is (= 1 (length hits)))
                    (is (string= "Lisp" (lucene:hit-field (first hits) "title"))))
               (lucene:close se))))
      (lucene:close dir))))
