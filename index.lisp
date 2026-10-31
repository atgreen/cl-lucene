;;;; index.lisp --- Writing documents into an index.
;;;;
;;;; Copyright (C) 2026  Anthony Green <green@moxielogic.com>
;;;; SPDX-License-Identifier: MIT

(in-package #:cl-lucene)

(defstruct (writer (:constructor %make-writer))
  "An open IndexWriter, with the directory and analyzer it uses, and the
FacetsConfig applied to each document so :facet fields become indexed facets."
  object
  directory
  analyzer
  facets-config
  owns-directory)

(defun open-mode (if-exists)
  "The IndexWriterConfig.OpenMode constant for IF-EXISTS."
  (java-static-field "org.apache.lucene.index.IndexWriterConfig$OpenMode"
                     (ecase if-exists
                       (:create "CREATE")
                       (:append "APPEND")
                       ((:create-or-append nil) "CREATE_OR_APPEND"))))

(defun make-writer (directory &key (analyzer :standard) (if-exists :create-or-append))
  "Open an IndexWriter on DIRECTORY (an INDEX-DIRECTORY).  ANALYZER names or is
an analyzer (see MAKE-ANALYZER).  IF-EXISTS is :create (start empty, discarding
any existing index), :append (require an existing index), or :create-or-append
(the default).  Close the result with CLOSE."
  (start)
  (let* ((analyzer (make-analyzer analyzer))
         (config (java-new "org.apache.lucene.index.IndexWriterConfig"
                           "(Lorg/apache/lucene/analysis/Analyzer;)" analyzer)))
    (java-call (concatenate 'string
                            "setOpenMode(Lorg/apache/lucene/index/IndexWriterConfig$OpenMode;)"
                            "Lorg/apache/lucene/index/IndexWriterConfig;")
               config (open-mode if-exists))
    (%make-writer
     :object (java-new "org.apache.lucene.index.IndexWriter"
                       "(Lorg/apache/lucene/store/Directory;Lorg/apache/lucene/index/IndexWriterConfig;)"
                       (dir-object directory) config)
     :directory directory
     :analyzer analyzer
     :facets-config (java-new "org.apache.lucene.facet.FacetsConfig" "()"))))

(defun build-document (fields)
  "A Lucene Document built from FIELDS, a list of field specs, each either a
Lucene field object or a list (NAME VALUE &key TYPE STORE) as MAKE-FIELD takes."
  (let ((document (java-new "org.apache.lucene.document.Document" "()")))
    (dolist (spec fields document)
      (java-call "add(Lorg/apache/lucene/index/IndexableField;)V"
                 document (field-spec->field spec)))))

(defun indexable-document (writer fields)
  "The document to index for WRITER from FIELDS: built, then passed through the
writer's FacetsConfig so any :facet fields become indexed facet doc-values.
For a document with no facet fields this is an equivalent document."
  (java-call "build(Lorg/apache/lucene/document/Document;)Lorg/apache/lucene/document/Document;"
             (writer-facets-config writer) (build-document fields)))

(defun add-document (writer fields)
  "Add one document to WRITER.  FIELDS is a list of field specs, each either a
Lucene field object or a list (NAME VALUE &key TYPE STORE) as MAKE-FIELD takes.
For example:
  (add-document w '((\"title\" \"The Lisp Machine\")
                    (\"id\" \"42\" :type :string)
                    (\"year\" 1985 :type :int)))"
  (with-foreign-errors ("Lucene")
    (java-call "addDocument(Ljava/lang/Iterable;)J" (writer-object writer)
               (indexable-document writer fields)))
  writer)

(defun delete-documents (writer target)
  "Delete documents from WRITER's index.  TARGET is either a query (a Query
object from the query builders) matching the documents to delete, or a term
given as (FIELD VALUE), deleting documents whose FIELD holds exactly VALUE."
  (with-foreign-errors ("Lucene")
    (if (consp target)
        (destructuring-bind (field value) target
          (java-call "deleteDocuments([Lorg/apache/lucene/index/Term;)J"
                     (writer-object writer)
                     (make-java-array-of "org.apache.lucene.index.Term"
                                         (list (term field value)))))
        (java-call "deleteDocuments([Lorg/apache/lucene/search/Query;)J"
                   (writer-object writer)
                   (make-java-array-of "org.apache.lucene.search.Query" (list target)))))
  writer)

(defun update-document (writer field value fields)
  "Replace the document whose FIELD holds exactly VALUE with a new document
built from FIELDS (as ADD-DOCUMENT takes), atomically.  FIELD should be a
:string/keyword field holding a unique key.  If no document matches, the new
document is simply added."
  (with-foreign-errors ("Lucene")
    (java-call "updateDocument(Lorg/apache/lucene/index/Term;Ljava/lang/Iterable;)J"
               (writer-object writer) (term field value) (indexable-document writer fields)))
  writer)

(defun commit (writer)
  "Flush WRITER's pending changes to the directory so searchers can see them."
  (with-foreign-errors ("Lucene")
    (java-call "commit()J" (writer-object writer)))
  writer)

(defun delete-all (writer)
  "Delete every document from WRITER's index."
  (with-foreign-errors ("Lucene")
    (java-call "deleteAll()J" (writer-object writer)))
  writer)

(defmethod close ((writer writer))
  (with-foreign-errors ("Lucene")
    (java-call "close()V" (writer-object writer)))
  (when (writer-owns-directory writer)
    (close (writer-directory writer)))
  (values))

(defun as-directory (target)
  "TARGET as (values INDEX-DIRECTORY OWNS-P): an INDEX-DIRECTORY is used as is
and not owned; anything else is opened with OPEN-DIRECTORY and owned."
  (if (index-directory-p target)
      (values target nil)
      (values (open-directory target) t)))

(defmacro with-writer ((var target &rest options) &body body)
  "Bind VAR to a writer on TARGET for the extent of BODY, then close it.  TARGET
is an INDEX-DIRECTORY, a path, or :MEMORY; a path or :MEMORY is opened into a
directory that is closed with the writer.  OPTIONS are MAKE-WRITER's keywords
(:analyzer, :if-exists)."
  (let ((directory (gensym "DIR")) (owns (gensym "OWNS")))
    `(multiple-value-bind (,directory ,owns) (as-directory ,target)
       (let ((,var (make-writer ,directory ,@options)))
         (setf (writer-owns-directory ,var) ,owns)
         (unwind-protect (progn ,@body)
           (close ,var))))))
