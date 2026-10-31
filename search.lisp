;;;; search.lisp --- Searching an index and reading back hits.
;;;;
;;;; Copyright (C) 2026  Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: MIT

(in-package #:cl-lucene)

(defstruct (searcher (:constructor %make-searcher))
  "An open IndexSearcher over a point-in-time view of an index, with the
directory, analyzer and default query field it searches."
  object
  reader
  directory
  analyzer
  default-field
  owns-directory)

(defun make-searcher (directory &key (analyzer :standard) (default-field "content"))
  "Open a searcher over DIRECTORY (an INDEX-DIRECTORY) as it stands now.  It
sees documents committed before it was opened; reopen to see later changes.
ANALYZER (see MAKE-ANALYZER) and DEFAULT-FIELD are used to parse string
queries.  Close the result with CLOSE."
  (start)
  (let ((reader (with-foreign-errors ("Lucene")
                  (java-static "org.apache.lucene.index.DirectoryReader"
                               "open(Lorg/apache/lucene/store/Directory;)Lorg/apache/lucene/index/DirectoryReader;"
                               (dir-object directory)))))
    (%make-searcher
     :object (java-new "org.apache.lucene.search.IndexSearcher"
                       "(Lorg/apache/lucene/index/IndexReader;)" reader)
     :reader reader
     :directory directory
     :analyzer (make-analyzer analyzer)
     :default-field (string default-field))))

(defmethod close ((searcher searcher))
  (java-call "close()V" (searcher-reader searcher))
  (when (searcher-owns-directory searcher)
    (close (searcher-directory searcher)))
  (values))

(defun parse-query (searcher query)
  "QUERY as a Lucene Query: a Query object is returned unchanged; a string is
parsed by the classic QueryParser over the searcher's default field."
  (if (stringp query)
      (let ((parser (java-new "org.apache.lucene.queryparser.classic.QueryParser"
                              "(Ljava/lang/String;Lorg/apache/lucene/analysis/Analyzer;)"
                              (jstring (searcher-default-field searcher))
                              (searcher-analyzer searcher))))
        (with-foreign-errors ("Lucene")
          (java-call "parse(Ljava/lang/String;)Lorg/apache/lucene/search/Query;"
                     parser (jstring query))))
      query))

;;; Reading stored fields back from a matching document

(defun number->lisp (number)
  "A Java java.lang.Number as the closest Lisp number."
  (cond ((java-instance-p number "java.lang.Double") (java-call "doubleValue()D" number))
        ((java-instance-p number "java.lang.Float") (java-call "floatValue()F" number))
        (t (java-call "longValue()J" number))))

(defun stored-field-value (field)
  "The stored value of a retrieved Lucene field, as a Lisp number for a numeric
field or a string otherwise.  NUMERICVALUE is consulted first because a stored
numeric field also reports a STRINGVALUE (the digits), which would otherwise
mask the number."
  (let ((number (java-call "numericValue()Ljava/lang/Number;" field)))
    (if number
        (number->lisp number)
        (let ((string (java-call "stringValue()Ljava/lang/String;" field)))
          (when string (lstring string))))))

(defun document-fields (document)
  "The stored fields of a retrieved DOCUMENT, as an alist of (name . value)."
  (let* ((fields (java-call "getFields()Ljava/util/List;" document))
         (count (java-call "size()I" fields)))
    (loop for i below count
          for field = (java-call "get(I)Ljava/lang/Object;" fields i)
          collect (cons (lstring (java-call "name()Ljava/lang/String;" field))
                        (stored-field-value field)))))

(defstruct (hit (:constructor %make-hit))
  "One search result: the document's internal ID, its relevance SCORE, and its
stored FIELDS as an alist of (name . value).  SCORE-DOC is the underlying Lucene
ScoreDoc, used as a cursor for paging with SEARCH's :after.  SNIPPET holds the
highlighted fragment when SEARCH was called with :highlight."
  id
  score
  fields
  score-doc
  snippet)

(defun highlight-snippets (searcher parsed top field)
  "Highlighted fragments (a list, one per hit in TOP, possibly NIL) of FIELD for
the query PARSED, via Lucene's UnifiedHighlighter and the searcher's analyzer."
  (let* ((highlighter (java-new "org.apache.lucene.search.uhighlight.UnifiedHighlighter"
                                "(Lorg/apache/lucene/search/IndexSearcher;Lorg/apache/lucene/analysis/Analyzer;)"
                                (searcher-object searcher) (searcher-analyzer searcher)))
         (array (java-call (concatenate 'string "highlight(Ljava/lang/String;"
                                        "Lorg/apache/lucene/search/Query;"
                                        "Lorg/apache/lucene/search/TopDocs;)[Ljava/lang/String;")
                           highlighter (jstring (string field)) parsed top)))
    (mapcar (lambda (snippet) (and snippet (lstring snippet))) (java-array-list array))))

(defun hit-field (hit name)
  "The stored value of field NAME in HIT, or NIL if the document has none."
  (cdr (assoc (string name) (hit-fields hit) :test #'string=)))

(defun score-doc->hit (searcher stored score-doc)
  "A HIT for the Lucene ScoreDoc SCORE-DOC, reading its stored fields through
STORED (SEARCHER's StoredFields)."
  (declare (ignore searcher))
  (let ((id (java-field-value score-doc "doc")))
    (%make-hit :id id
               :score (java-field-value score-doc "score")
               :score-doc score-doc
               :fields (document-fields
                        (java-call "document(I)Lorg/apache/lucene/document/Document;" stored id)))))

(defun searcher-stored-fields (searcher)
  "SEARCHER's StoredFields, for reading documents."
  (java-call "storedFields()Lorg/apache/lucene/index/StoredFields;" (searcher-object searcher)))

(defparameter *sort-types*
  '((:int . "INT") (:long . "LONG") (:float . "FLOAT") (:double . "DOUBLE")
    (:string . "STRING") (:keyword . "STRING"))
  "Keyword names for the SortField.Type values a field sort can use.")

(defun sort-field (key)
  "A Lucene SortField from a sort KEY: :relevance/:score, :doc, or
(FIELD TYPE &optional DIRECTION) where TYPE is one of *SORT-TYPES* and
DIRECTION is :asc (default) or :desc."
  (case key
    ((:relevance :score)
     (java-new "org.apache.lucene.search.SortField"
               "(Ljava/lang/String;Lorg/apache/lucene/search/SortField$Type;)"
               nil (java-static-field "org.apache.lucene.search.SortField$Type" "SCORE")))
    ((:doc)
     (java-new "org.apache.lucene.search.SortField"
               "(Ljava/lang/String;Lorg/apache/lucene/search/SortField$Type;)"
               nil (java-static-field "org.apache.lucene.search.SortField$Type" "DOC")))
    (t
     (destructuring-bind (field type &optional (direction :asc)) key
       (let ((reverse (if (eq direction :desc) 1 0)))
         (cond
           ;; Numeric fields (:int/:long/:float/:double) are indexed with
           ;; SortedNumericDocValues, read by SortedNumericSortField.
           ((member type '(:int :long :float :double))
            (java-new "org.apache.lucene.search.SortedNumericSortField"
                      "(Ljava/lang/String;Lorg/apache/lucene/search/SortField$Type;Z)"
                      (jstring (string field))
                      (java-static-field "org.apache.lucene.search.SortField$Type"
                                         (cdr (assoc type *sort-types*)))
                      reverse))
           ;; :string/:keyword fields (KeywordField) carry SortedSetDocValues,
           ;; read by SortedSetSortField.
           ((member type '(:string :keyword))
            (java-new "org.apache.lucene.search.SortedSetSortField"
                      "(Ljava/lang/String;Z)" (jstring (string field)) reverse))
           (t (error "Unknown sort type ~S" type))))))))

(defun normalize-sort (sort)
  "SORT as a list of sort keys.  A bare keyword (:score) or a single
(FIELD TYPE ...) key becomes a one-element list; a list of keys is returned
as is."
  (if (keywordp sort)
      (list sort)
      (let ((head (first sort)))
        (if (or (keywordp head) (consp head))
            sort                ; already a list of keys
            (list sort)))))     ; a single (FIELD TYPE ...) key

(defun build-sort (sort)
  "A Lucene Sort from SORT, a single sort key or a list of keys (see SORT-FIELD)."
  (java-new "org.apache.lucene.search.Sort"
            "([Lorg/apache/lucene/search/SortField;)"
            (make-java-array-of "org.apache.lucene.search.SortField"
                                (mapcar #'sort-field (normalize-sort sort)))))

(defun run-top-docs (searcher parsed limit sort after)
  "Call the right IndexSearcher.search / searchAfter variant and return its
TopDocs.  AFTER, when given, is a HIT (or raw ScoreDoc) marking where a
previous page ended."
  (let ((object (searcher-object searcher))
        (cursor (and after (if (hit-p after) (hit-score-doc after) after))))
    (cond
      ((and cursor sort)
       (java-call (concatenate 'string "searchAfter(Lorg/apache/lucene/search/ScoreDoc;"
                               "Lorg/apache/lucene/search/Query;ILorg/apache/lucene/search/Sort;)"
                               "Lorg/apache/lucene/search/TopFieldDocs;")
                  object cursor parsed limit (build-sort sort)))
      (cursor
       (java-call (concatenate 'string "searchAfter(Lorg/apache/lucene/search/ScoreDoc;"
                               "Lorg/apache/lucene/search/Query;I)Lorg/apache/lucene/search/TopDocs;")
                  object cursor parsed limit))
      (sort
       (java-call (concatenate 'string "search(Lorg/apache/lucene/search/Query;I"
                               "Lorg/apache/lucene/search/Sort;)Lorg/apache/lucene/search/TopFieldDocs;")
                  object parsed limit (build-sort sort)))
      (t
       (java-call "search(Lorg/apache/lucene/search/Query;I)Lorg/apache/lucene/search/TopDocs;"
                  object parsed limit)))))

(defun search (searcher query &key (limit 10) sort after highlight)
  "Search for QUERY (a query string or a Lucene Query).  Returns two values:
up to LIMIT HITs, and the total number of matching documents.  Without SORT the
hits come most-relevant first; SORT is a sort key or list of keys (see
SORT-FIELD), e.g. '(\"year\" :int :desc) or (list '(\"year\" :int :desc) :score).
AFTER is a HIT from a previous page (its last one); the search then resumes
after it, for paging through more than LIMIT results.  HIGHLIGHT, a field name,
fills each hit's SNIPPET with a highlighted fragment of that field.  Each hit
carries its score, its stored fields, and a cursor for the next page's :after."
  (start)
  (with-foreign-errors ("Lucene")
    (let* ((parsed (parse-query searcher query))
           (top (run-top-docs searcher parsed limit sort after))
           (total (java-call "value()J" (java-field-value top "totalHits")))
           (score-docs (java-array-list (java-field-value top "scoreDocs")))
           (snippets (when highlight (highlight-snippets searcher parsed top highlight)))
           (stored (searcher-stored-fields searcher)))
      (values
       (loop for score-doc in score-docs
             for index from 0
             for hit = (score-doc->hit searcher stored score-doc)
             do (when snippets (setf (hit-snippet hit) (nth index snippets)))
             collect hit)
       total))))

(defun explain (searcher query hit-or-id)
  "Explain how QUERY scored a document, for debugging relevance.  HIT-OR-ID is a
HIT from SEARCH or a raw internal document id.  Returns two values: a
human-readable explanation string and the Lucene Explanation object."
  (start)
  (with-foreign-errors ("Lucene")
    (let* ((id (if (hit-p hit-or-id) (hit-id hit-or-id) hit-or-id))
           (explanation (java-call "explain(Lorg/apache/lucene/search/Query;I)Lorg/apache/lucene/search/Explanation;"
                                   (searcher-object searcher) (parse-query searcher query) id)))
      (values (lstring (java-call "toString()Ljava/lang/String;" explanation))
              explanation))))

(defun search-count (searcher query)
  "The number of documents matching QUERY, without fetching them."
  (start)
  (with-foreign-errors ("Lucene")
    (java-call "count(Lorg/apache/lucene/search/Query;)I"
               (searcher-object searcher) (parse-query searcher query))))

(defmacro with-searcher ((var target &rest options) &body body)
  "Bind VAR to a searcher on TARGET for the extent of BODY, then close it.
TARGET is an INDEX-DIRECTORY or a path; a path is opened into a directory that
is closed with the searcher.  OPTIONS are MAKE-SEARCHER's keywords (:analyzer,
:default-field)."
  (let ((directory (gensym "DIR")) (owns (gensym "OWNS")))
    `(multiple-value-bind (,directory ,owns) (as-directory ,target)
       (let ((,var (make-searcher ,directory ,@options)))
         (setf (searcher-owns-directory ,var) ,owns)
         (unwind-protect (progn ,@body)
           (close ,var))))))
