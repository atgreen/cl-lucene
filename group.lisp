;;;; group.lisp --- Grouping search results.
;;;;
;;;; Copyright (C) 2026  Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: MIT
;;;;
;;;; Collapse results into groups sharing a field value (Lucene's
;;;; GroupingSearch), e.g. search results grouped by author or category.  The
;;;; group field must be a single-valued SortedDocValues field -- a
;;;; :sorted-string field (not a :string, which is multi-valued SortedSet).

(in-package #:cl-lucene)

(defstruct (group (:constructor %make-group))
  "One result group: the shared field VALUE, its top HITS, and the TOTAL number
of documents in the group."
  value
  hits
  total)

(defun group-search (searcher query group-field &key (limit 10) (hits-per-group 1))
  "Group QUERY's results by GROUP-FIELD (a :sorted-string field name).  Returns
up to LIMIT GROUPs, each with up to HITS-PER-GROUP hits and the group's total
count.  Groups come most-relevant first."
  (start)
  (with-foreign-errors ("Lucene")
    (let* ((grouping (java-new "org.apache.lucene.search.grouping.GroupingSearch"
                               "(Ljava/lang/String;)" (jstring (string group-field))))
           (stored (searcher-stored-fields searcher)))
      (java-call "setGroupDocsLimit(I)Lorg/apache/lucene/search/grouping/GroupingSearch;"
                 grouping hits-per-group)
      (let* ((top-groups (java-call (concatenate 'string
                                                 "search(Lorg/apache/lucene/search/IndexSearcher;"
                                                 "Lorg/apache/lucene/search/Query;II)"
                                                 "Lorg/apache/lucene/search/grouping/TopGroups;")
                                    grouping (searcher-object searcher)
                                    (parse-query searcher query) 0 limit))
             (groups (java-array-list (java-field-value top-groups "groups"))))
        (loop for group-docs in groups
              for value = (java-call "groupValue()Ljava/lang/Object;" group-docs)
              collect (%make-group
                       :value (and value (lstring (java-call "utf8ToString()Ljava/lang/String;" value)))
                       :total (java-call "value()J"
                                         (java-call "totalHits()Lorg/apache/lucene/search/TotalHits;" group-docs))
                       :hits (mapcar (lambda (score-doc) (score-doc->hit searcher stored score-doc))
                                     (java-array-list
                                      (java-call "scoreDocs()[Lorg/apache/lucene/search/ScoreDoc;" group-docs)))))))))
