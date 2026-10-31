;;;; query.lisp --- Programmatic query builders.
;;;;
;;;; Copyright (C) 2026  Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: MIT
;;;;
;;;; These build Lucene Query objects directly, as an alternative to the query
;;;; strings MAKE-SEARCHER parses.  Any of them can be passed to SEARCH,
;;;; SEARCH-COUNT, or combined with BOOLEAN-QUERY.

(in-package #:cl-lucene)

(defun term (field value)
  "A Lucene Term naming an exact VALUE in FIELD."
  (java-new "org.apache.lucene.index.Term"
            "(Ljava/lang/String;Ljava/lang/String;)"
            (jstring (string field)) (jstring (princ-to-string value))))

(defun match-all-query ()
  "A query matching every document."
  (start)
  (java-new "org.apache.lucene.search.MatchAllDocsQuery" "()"))

(defun term-query (field value)
  "A query matching documents whose FIELD contains the exact term VALUE."
  (start)
  (java-new "org.apache.lucene.search.TermQuery"
            "(Lorg/apache/lucene/index/Term;)" (term field value)))

(defun phrase-query (field terms &key (slop 0))
  "A query matching the TERMS appearing in FIELD as a phrase.  SLOP is how many
position moves are tolerated between them (0 means an exact, adjacent phrase)."
  (start)
  (java-new "org.apache.lucene.search.PhraseQuery"
            "(ILjava/lang/String;[Ljava/lang/String;)"
            slop (jstring (string field))
            (make-java-array-of "java.lang.String"
                                (mapcar (lambda (term) (jstring (princ-to-string term))) terms))))

(defun prefix-query (field prefix)
  "A query matching documents whose FIELD has a term starting with PREFIX."
  (start)
  (java-new "org.apache.lucene.search.PrefixQuery"
            "(Lorg/apache/lucene/index/Term;)" (term field prefix)))

(defun wildcard-query (field pattern)
  "A query matching FIELD terms against PATTERN, where ? is any one character
and * is any run of characters."
  (start)
  (java-new "org.apache.lucene.search.WildcardQuery"
            "(Lorg/apache/lucene/index/Term;)" (term field pattern)))

(defun fuzzy-query (field value)
  "A query matching FIELD terms within a small edit distance of VALUE."
  (start)
  (java-new "org.apache.lucene.search.FuzzyQuery"
            "(Lorg/apache/lucene/index/Term;)" (term field value)))

(defun regexp-query (field pattern)
  "A query matching FIELD terms against the regular expression PATTERN (Lucene's
regexp syntax, anchored to the whole term)."
  (start)
  (java-new "org.apache.lucene.search.RegexpQuery"
            "(Lorg/apache/lucene/index/Term;)" (term field pattern)))

(defun boost-query (query boost)
  "Wrap QUERY so its scores are multiplied by BOOST, raising or lowering its
contribution within a BOOLEAN-QUERY without changing which documents match."
  (start)
  (java-new "org.apache.lucene.search.BoostQuery"
            "(Lorg/apache/lucene/search/Query;F)" query (coerce boost 'single-float)))

(defun near-query (field terms &key (max-gaps 0) (ordered t))
  "A proximity query: the TERMS (a list of strings) appear in FIELD within
MAX-GAPS positions of each other, in order when ORDERED (the default) or in any
order otherwise.  Built on Lucene's interval queries."
  (start)
  (flet ((intervals (method &rest args)
           (apply #'java-static "org.apache.lucene.queries.intervals.Intervals" method args)))
    (let* ((sources (make-java-array-of "org.apache.lucene.queries.intervals.IntervalsSource"
                                        (mapcar (lambda (term)
                                                  (intervals "term(Ljava/lang/String;)Lorg/apache/lucene/queries/intervals/IntervalsSource;"
                                                             (jstring (princ-to-string term))))
                                                terms)))
           (combined (intervals (if ordered
                                    "ordered([Lorg/apache/lucene/queries/intervals/IntervalsSource;)Lorg/apache/lucene/queries/intervals/IntervalsSource;"
                                    "unordered([Lorg/apache/lucene/queries/intervals/IntervalsSource;)Lorg/apache/lucene/queries/intervals/IntervalsSource;")
                                sources))
           ;; maxgaps bounds the tokens allowed between the terms; 0 means they
           ;; must be adjacent.  Always applied, so :max-gaps 0 is a true phrase.
           (source (intervals "maxgaps(ILorg/apache/lucene/queries/intervals/IntervalsSource;)Lorg/apache/lucene/queries/intervals/IntervalsSource;"
                              max-gaps combined)))
      (java-new "org.apache.lucene.queries.intervals.IntervalQuery"
                "(Ljava/lang/String;Lorg/apache/lucene/queries/intervals/IntervalsSource;)"
                (jstring (string field)) source))))

(defun geo-distance-query (field latitude longitude radius-meters)
  "A query matching :geo FIELD points within RADIUS-METERS of (LATITUDE LONGITUDE)."
  (start)
  (java-static "org.apache.lucene.document.LatLonPoint"
               "newDistanceQuery(Ljava/lang/String;DDD)Lorg/apache/lucene/search/Query;"
               (jstring (string field)) (coerce latitude 'double-float)
               (coerce longitude 'double-float) (coerce radius-meters 'double-float)))

(defun geo-box-query (field min-latitude max-latitude min-longitude max-longitude)
  "A query matching :geo FIELD points inside the given latitude/longitude box."
  (start)
  (java-static "org.apache.lucene.document.LatLonPoint"
               "newBoxQuery(Ljava/lang/String;DDDD)Lorg/apache/lucene/search/Query;"
               (jstring (string field)) (coerce min-latitude 'double-float)
               (coerce max-latitude 'double-float) (coerce min-longitude 'double-float)
               (coerce max-longitude 'double-float)))

(defun knn-query (field vector &key (k 10) filter)
  "A k-nearest-neighbour query over the :vector FIELD: the K documents whose
stored vector is closest to VECTOR (a sequence of reals).  FILTER, if given, is
a Query restricting the documents considered."
  (start)
  (if filter
      (java-new "org.apache.lucene.search.KnnFloatVectorQuery"
                "(Ljava/lang/String;[FILorg/apache/lucene/search/Query;)"
                (jstring (string field)) (float-array vector) k filter)
      (java-new "org.apache.lucene.search.KnnFloatVectorQuery"
                "(Ljava/lang/String;[FI)"
                (jstring (string field)) (float-array vector) k)))

(defparameter *numeric-range*
  '((:int    "org.apache.lucene.document.IntField"    "newRangeQuery(Ljava/lang/String;II)Lorg/apache/lucene/search/Query;"   -2147483648            2147483647)
    (:long   "org.apache.lucene.document.LongField"   "newRangeQuery(Ljava/lang/String;JJ)Lorg/apache/lucene/search/Query;"   -9223372036854775808   9223372036854775807)
    (:float  "org.apache.lucene.document.FloatField"  "newRangeQuery(Ljava/lang/String;FF)Lorg/apache/lucene/search/Query;"   nil                    nil)
    (:double "org.apache.lucene.document.DoubleField" "newRangeQuery(Ljava/lang/String;DD)Lorg/apache/lucene/search/Query;"   nil                    nil))
  "Per numeric TYPE: the field class, its newRangeQuery descriptor, and the
default lower/upper bounds for an open end (NIL means the float/double extreme,
filled in by RANGE-QUERY).")

(defun range-query (field &key min max (type :int) (include-min t) (include-max t))
  "A query matching documents whose FIELD value lies in a range.  TYPE selects
how FIELD is interpreted:
  :int :long :float :double  a numeric range [MIN, MAX], inclusive; an omitted
                             bound opens that end.  INCLUDE-MIN/INCLUDE-MAX do
                             not apply and are ignored.
  :text :string              a lexicographic term range; here INCLUDE-MIN and
                             INCLUDE-MAX (default T) choose open or closed ends,
                             and an omitted bound opens that end."
  (start)
  (if (member type '(:text :string :keyword))
      (java-static "org.apache.lucene.search.TermRangeQuery"
                   (concatenate 'string "newStringRange(Ljava/lang/String;Ljava/lang/String;"
                                "Ljava/lang/String;ZZ)Lorg/apache/lucene/search/TermRangeQuery;")
                   (jstring (string field))
                   (and min (jstring (princ-to-string min)))
                   (and max (jstring (princ-to-string max)))
                   (if include-min 1 0) (if include-max 1 0))
      (destructuring-bind (class descriptor default-min default-max)
          (or (cdr (assoc type *numeric-range*))
              (error "Unknown range type ~S" type))
        (flet ((bound (value default extreme)
                 (cond (value (ecase type
                                (:int (round value)) (:long (round value))
                                (:float (coerce value 'single-float))
                                (:double (coerce value 'double-float))))
                       (default default)
                       (t (funcall extreme)))))
          (java-static class descriptor (jstring (string field))
                       (bound min default-min
                              (if (eq type :float)
                                  (lambda () most-negative-single-float)
                                  (lambda () most-negative-double-float)))
                       (bound max default-max
                              (if (eq type :float)
                                  (lambda () most-positive-single-float)
                                  (lambda () most-positive-double-float))))))))

(defparameter *occurs*
  '((:must . "MUST") (:should . "SHOULD") (:must-not . "MUST_NOT") (:filter . "FILTER"))
  "Keyword names for BooleanClause.Occur values.")

(defun occur (keyword)
  (java-static-field "org.apache.lucene.search.BooleanClause$Occur"
                     (or (cdr (assoc keyword *occurs*))
                         (error "Unknown occur ~S" keyword))))

(defun boolean-query (&key must should must-not filter (min-should-match 0))
  "Combine queries into a BooleanQuery.  MUST clauses must all match, SHOULD
clauses contribute to the score (and at least MIN-SHOULD-MATCH of them must
match), MUST-NOT clauses must not match, and FILTER clauses must match but do
not affect the score.  Each keyword takes a single query or a list of queries."
  (start)
  (let ((builder (java-new "org.apache.lucene.search.BooleanQuery$Builder" "()")))
    (flet ((add-clauses (queries keyword)
             (dolist (query (if (listp queries) queries (list queries)))
               (when query
                 (java-call (concatenate 'string "add(Lorg/apache/lucene/search/Query;"
                                         "Lorg/apache/lucene/search/BooleanClause$Occur;)"
                                         "Lorg/apache/lucene/search/BooleanQuery$Builder;")
                            builder query (occur keyword))))))
      (add-clauses must :must)
      (add-clauses should :should)
      (add-clauses must-not :must-not)
      (add-clauses filter :filter))
    (when (plusp min-should-match)
      (java-call "setMinimumNumberShouldMatch(I)Lorg/apache/lucene/search/BooleanQuery$Builder;"
                 builder min-should-match))
    (java-call "build()Lorg/apache/lucene/search/BooleanQuery;" builder)))
