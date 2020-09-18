;;; -*- Mode: Lisp; indent-tabs-mode: nil -*-
;;;
;;; generate.lisp --- generate CFFI bindings from vk.xml file.
;;;
;;; Copyright (c) 2016, Bart Botta  <00003b@gmail.com>
;;;   All rights reserved.
;;;
;;; Permission is hereby granted, free of charge, to any person
;;; obtaining a copy of this software and associated documentation
;;; files (the "Software"), to deal in the Software without
;;; restriction, including without limitation the rights to use, copy,
;;; modify, merge, publish, distribute, sublicense, and/or sell copies
;;; of the Software, and to permit persons to whom the Software is
;;; furnished to do so, subject to the following conditions:
;;;
;;; The above copyright notice and this permission notice shall be
;;; included in all copies or substantial portions of the Software.
;;;
;;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
;;; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
;;; MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
;;; NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
;;; HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
;;; WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;;; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
;;; DEALINGS IN THE SOFTWARE.
;;;

(in-package :vk-generator/generate)

(defparameter *in-package-name* "cl-vulkan-bindings")
(defparameter *package-nicknames* "#:%vk")
(defparameter *core-definer* "defvkfun")
(defparameter *ext-definer* "defvkextfun")

;; from generator.py
(defparameter *ext-base* 1000000000)
(defparameter *ext-block-size* 1000)

(defparameter *vk-api-version* nil) ;; (major minor patch)
(defparameter *vk-last-updated* nil)

(defparameter *api-constants* (make-hash-table :test 'equal))

(defvar *handle-types*)

;; not sure if we should remove the type prefixes in struct members or
;; not?
;;(defparameter *type-prefixes* '("s-" "p-" "pfn-" "pp-"))
          
;; todo: split this up into parser-functions & writer-functions
(defun generate-vk-package (vk-xml-pathname out-dir)
  ;; read from data files
  (let* ((vk-dir out-dir)
         (binding-package-file (merge-pathnames "bindings-package.lisp" vk-dir))
         (translators-file (merge-pathnames "translators.lisp" vk-dir))
         (types-file (merge-pathnames "types.lisp" vk-dir))
         (funcs-file (merge-pathnames "funcs.lisp" vk-dir))
         #++(name-map (read-name-map vk-dir))
         #++(types (read-known-types vk-dir))
         (vk.xml (cxml:parse-file vk-xml-pathname
                                  (cxml:make-whitespace-normalizer
                                   (stp:make-builder))))
         (copyright (xpath:string-value
                     (xpath:evaluate "/registry/comment" vk.xml)))
         (bitfields (make-hash-table :test 'equal))
         #++(types (alexandria:copy-hash-table *vk-platform* :test 'equal))
         (types nil) ;; structs are ordered, so use an alist (actually need to order by hand anyway, so probably should switch back to hash)
         (enums (make-hash-table :test 'equal))
         (structs (make-hash-table :test 'equal))
         (funcs (make-hash-table :test 'equal))
         (function-apis (make-hash-table :test 'equal))
         (extension-names (make-hash-table :test 'equal))
         (*handle-types* (make-hash-table :test 'equal))
         ;; todo: handle aliases - for now alias names are stored here so processing can be skipped for them further down
         (alias-names nil)
         #++(old-bindings (load-bindings vk-dir))
         #++(old-enums (load-enums vk-dir))
         (vendor-ids (extract-vendor-ids vk.xml))) ;; extract tags / vendor-ids
    (flet ((get-type (name)
             (cdr (assoc name types :test 'string=)))
           (get-type/f (name)
             (cdr (assoc name types :test (lambda (a b)
                                            (equalp
                                             (fix-type-name a vendor-ids)
                                             (fix-type-name b vendor-ids)))))))
      ;; remove some other text from the comment if present
      (let ((s (search "This file, vk.xml, is the " copyright)))
        (when s (setf copyright (string-trim '(#\space #\tab #\newline #\return)
                                             (subseq copyright 0 s)))))
      ;; make sure we still have a copyright notice
      (assert (search "Copyright" copyright))

      ;; extract version info
      (let ((api (xpath:string-value
                  (xpath:evaluate "/registry/types/type/name[.=\"VK_API_VERSION\"]/.." vk.xml))))
        ;; #define VK_API_VERSION VK_MAKE_VERSION(1, 0, 3)
        (setf *vk-api-version* (map 'list 'parse-integer
                                    (nth-value 1 (ppcre::scan-to-strings "\\((\\d+),\\W*(\\d+),\\W*(\\d+)\\)" api)))))

      ;; extra pass to find struct/unions so we can mark them correctly
      ;; in member types
      (xpath:do-node-set (node (xpath:evaluate "/registry/types/type[(@category=\"struct\") or (@category=\"union\")]" vk.xml))
        (let ((name (xps (xpath:evaluate "@name" node)))
              (category (xps (xpath:evaluate "@category" node))))
          (setf (gethash (fix-type-name name vendor-ids) structs)
                (make-keyword category))))

      ;; and extract "API constants" enum first too for member array sizes
      (xpath:do-node-set (enum (xpath:evaluate "/registry/enums[(@name=\"API Constants\")]/enum" vk.xml))
        (let ((name (xps (xpath:evaluate "@name" enum)))
              (value (numeric-value (xps (xpath:evaluate "@value" enum))))
              (alias (xps (xpath:evaluate "@alias" enum))))
          (if alias
              (warn "ALIAS NOT HANDLED YET: ~s is alias for ~s~%" name alias)
              (progn
                (when (gethash name *api-constants*)
                  (assert (= value (gethash name *api-constants*))))
                (setf (gethash name *api-constants*) value)))))

      ;; extract handle types so we can mark them as pointers for translators
      (xpath:do-node-set (node (xpath:evaluate "/registry/types/type[(@category=\"handle\")]" vk.xml))
        (let ((name (xps (xpath:evaluate "name" node))))
          (setf (gethash name *handle-types*) t)))

      ;; extract types
      ;; todo:? VK_DEFINE_HANDLE VK_DEFINE_NON_DISPATCHABLE_HANDLE
      ;; #define VK_NULL_HANDLE 0
      (xpath:do-node-set (node (xpath:evaluate "/registry/types/type[not(apientry) and not(@category=\"include\") and not(@category=\"define\")]" vk.xml))
        (let ((name (xps (xpath:evaluate "name" node)))
              (@name (xps (xpath:evaluate "@name" node)))
              (alias (xps (xpath:evaluate "@alias" node)))
              (type (xps (xpath:evaluate "type" node)))
              (type* (mapcar 'xpath:string-value (xpath:all-nodes (xpath:evaluate "type" node))))
              (category (xps (xpath:evaluate "@category" node)))
              (parent (xps (xpath:evaluate "@parent" node)))
              (requires (xps (xpath:evaluate "@requires" node)))
              (comment (xps (xpath:evaluate "@comment" node)))
              (returnedonly (xps (xpath:evaluate "@returnedonly" node)))
              (attribs (attrib-names node))
              ;; required since v1.2.140 which changes some "define" types to "basetype" types with prefix "struct"
              (prefix (xps (xpath:evaluate "type/preceding-sibling::text()" node))))
          ;; make sure nobody added any attributes we might care about
          (assert (not (set-difference attribs
                                       ;; todo: provide set per version-tag
                                       '("name" "category" "parent" "requires"
                                         "comment"
                                         ;; todo: the attributes below are not handled yet
                                         "returnedonly"
                                         ;; todo: only from v1.0.55-core
                                         "structextends"
                                         ;; todo: only from v1.1.70
                                         "alias"
                                         ;; todo: only from v1.2.140
                                         "allowduplicate"
                                         )
                                       :test 'string=)))
          (flet ((set-type (value)
                   (let ((name (or name @name)))
                     (if (get-type name)
                         (assert (equalp value (get-type name)))
                         (push (cons name value) types)))))
            (cond
              ((string= requires "vk_platform")
               ;; make sure we have a mapping for everything in vk_platform.h
               (assert (gethash @name *vk-platform*)))
              ((and requires (search ".h" requires))
               ;; and make a note of other missing types
               ;; (not sure if we will need definitions for these or not?)
               (unless (gethash @name *vk-platform*)
                 (format t "Unknown platform type ~s from ~s (~s)?~%" @name requires name)))
              (alias
               (push @name alias-names)
               (warn "ALIAS NOT HANDLED YET: ~s is alias for ~s and has category ~a~%" @name alias category))
              ((and (string= category "basetype")
                    (not (string= prefix "typedef")))
               (format t "Skipping opaque type: ~s~%" name))
              ((string= category "basetype")
               ;; basetypes
               (assert (and name type))
               (format t "new base type ~s -> ~s~%" name type)
               (set-type (list :basetype (or (gethash type *vk-platform*)
                                          (fix-type-name type vendor-ids)))))
              ((string= category "bitmask")
               (format t "new bitmask ~s -> ~s~%  ~s~%" name type
                       (mapcar 'xps (xpath:all-nodes (xpath:evaluate "@*" node))))
               (setf (gethash name bitfields) (list requires :type type))
               (set-type (list :bitmask type)))
              ((string= category "handle")
               (let ((dispatch (cond
                                 ((string= type "VK_DEFINE_HANDLE")
                                  :handle)
                                 ((string= type "VK_DEFINE_NON_DISPATCHABLE_HANDLE")
                                  :non-dispatch-handle)
                                 (t
                                  (error "unknown handle type ~s?" type)))))
                 (format t "new handle ~s / ~s ~s~%" parent name type)
                 (set-type (list dispatch type))))
              ((string= category "enum")
               (assert (not (or requires type name parent)))
               (format t "new enum type ~s ~s~%" @name type)
               (set-type (list :enum type)))
              ((string= category "funcpointer")
               (format t "new function pointer type ~s ~s~%" name type*)
               (let* ((types (mapcar 'xps (xpath:all-nodes (xpath:evaluate "type" node))))
                      (before-name (xps (xpath:evaluate "name/preceding-sibling::text()" node)))
                      (rt (ppcre:regex-replace-all "(^typedef | \\(VKAPI_PTR \\*$)"
                                                   before-name ""))
                      (before (xpath:all-nodes (xpath:evaluate "type/preceding-sibling::text()" node)))
                      (after (xpath:all-nodes (xpath:evaluate "type/following-sibling::text()" node)))
                      (args (loop for at in types
                                  for a in after
                                  for b in before
                                  for star = (count #\* (xps a))
                                  for const = (search "const" (xps b))
                                  for an = (ppcre:regex-replace-all "(\\*|\\W|,|const|\\)|;)" (xps a) "")
                                  when (plusp star) do (assert (= star 1))
                                    collect (list (format nil "~a~@[/const~]"
                                                          an const)
                                                  (if (plusp star)
                                                      `(:pointer ,(fix-type-name at vendor-ids))
                                                      (fix-type-name at vendor-ids))))))
                 (let ((c (count #\* rt)))
                   (setf rt (fix-type-name (string-right-trim '(#\*) rt) vendor-ids))
                   (setf rt (or (gethash rt *vk-platform*) rt))
                   (loop repeat c do (setf rt (list :pointer rt))))
                 (set-type (list :func :type (list rt args)))))
              ((or (string= category "struct")
                   (string= category "union"))
               (let ((members nil))
                 (xpath:do-node-set (member (xpath:evaluate "member" node))
                   (push (parse-arg-type member
                                         (lambda (a) (gethash a structs))
                                         vendor-ids
                                         *api-constants*
                                         *handle-types*
                                         :stringify returnedonly)
                         members))
                 (setf members (nreverse members))
                 (format t "new ~s ~s: ~%~{  ~s~^~%~}~%"
                         category @name members)
                 (set-type `(,(if (string= category "struct")
                                  :struct
                                  :union)
                             , @name
                             :members ,members
                             :returned-only ,returnedonly
                             ,@(when comment (list :comment comment))))))
              (t
               (format t "unknown type category ~s for name ~s~%"
                      category (or name @name)))))))

;;; enums*
      (xpath:do-node-set (node (xpath:evaluate "/registry/enums" vk.xml))
        (let* ((name (xps (xpath:evaluate "@name" node)))
               (comment (xps (xpath:evaluate "@comment" node)))
               (type (xps (xpath:evaluate "@type" node)))
               (expand (xps (xpath:evaluate "@expand" node)))
               (namespace (xps (xpath:evaluate "@namespace" node)))
               (attribs  (attrib-names node))
               (enums (xpath:all-nodes (xpath:evaluate "enum" node)))
               (enum-type (get-type name)))
          ;; make sure nobody added any attributes we might care about
          (assert (not (set-difference attribs
                                       '("namespace" "name"
                                         "type" "expand" "comment")
                                       :test 'string=)))
          (unless (string= name "API Constants")
            ;; v1.1.124 adds VkSemaphoreCreateFlagBits enum type which is missing in enum section and must be created here
            (if (and (not enum-type)
                     (string= name "VkSemaphoreCreateFlagBits"))
                (progn
                  (push (cons name (list :enum nil)) types)
                  (format t "new enum type ~s~%" name)
                  (setf enum-type (get-type name)))
                (assert (get-type name))))
          (assert (not (second enum-type)))
          (loop for enum in enums
                for name2 = (xps (xpath:evaluate "@name" enum))
                for value = (numeric-value (xps (xpath:evaluate "@value" enum)))
                for bitpos = (numeric-value (xps (xpath:evaluate "@bitpos" enum)))
                for comment2 = (xps (xpath:evaluate "@comment" enum))
                ;; since v1.1.83
                for alias = (xps (xpath:evaluate "@alias" enum))
                unless (string= name "API Constants")
                  do (if alias
                         (warn "ALIAS NOT YET HANDLED: ~s is an alias for ~s" name2 alias)
                         (progn
                           (assert (not (and bitpos value)))
                           (assert (or bitpos value))
                           (push `(,name2 ,(or value (ash 1 bitpos))
                                          ,@(when comment2 (list :comment comment2)))
                                 (second enum-type)))))
          (when (second enum-type)
            (setf (second enum-type)
                  (nreverse (second enum-type))))
          (when type
            (setf (getf (cddr enum-type) :type) (make-keyword type))
            (format t "add bitmask ~s ~s~%" name type)
            (when (and (string= type "bitmask")
                       (not (gethash name bitfields)))
              (setf (gethash name bitfields)
                    (list nil :type nil))))
          (when expand
            (setf (getf (cddr enum-type) :expand) expand))
          (when namespace
            (setf (getf (cddr enum-type) :namespace) namespace))))

;;; commands
      (xpath:do-node-set (node (xpath:evaluate "/registry/commands/command" vk.xml))
        (let* ((name (xps (xpath:evaluate "proto/name" node)))
               (type (xps (xpath:evaluate "proto/type" node)))
               (alias (xps (xpath:evaluate "@alias" node)))
               (@name (xps (xpath:evaluate "@name" node)))
               #++(proto (xpath:evaluate "proto" node))
               (.params (xpath:all-nodes (xpath:evaluate "param" node)))
               (successcodes (xps (xpath:evaluate "@successcodes" node)))
               (errorcodes (xps (xpath:evaluate "@errorcodes" node)))
               (queues (xps (xpath:evaluate "@queues" node)))
               (cmdbufferlevel (xps (xpath:evaluate "@cmdbufferlevel" node)))
               (renderpass (xps (xpath:evaluate "@renderpass" node)))
               (pipeline (xps (xpath:evaluate "@pipeline" node)))
               (attribs (attrib-names node)))
          ;; make sure nobody added any attributes we might care about
          (assert (not (set-difference attribs
                                       '("successcodes" "errorcodes" "queues"
                                         "cmdbufferlevel" "renderpass"
                                         ;; todo:
                                         "pipeline" "comment"
                                         ;; todo: only from v1.1.70
                                         "alias" "name"
                                         )
                                       :test 'string=)))
          (if alias
              (progn
                (push @name alias-names)
                (warn "ALIAS NOT HANDLED YET: ~s is alias for ~s~%" @name alias))
              (let ((params
                      (loop for p in .params
                            for optional = (xps (xpath:evaluate "@optional" p))
                            for externsync = (xps (xpath:evaluate "@externsync" p))
                            for len = (xps (xpath:evaluate "@len" p))
                            for noautovalidity = (xps (xpath:evaluate "@noautovalidity" p))
                            for desc = (parse-arg-type p
                                                       (lambda (a) (gethash a structs))
                                                       vendor-ids
                                                       *api-constants*
                                                       *handle-types*
                                                       :stringify t)
                            for attribs = (attrib-names p)
                            do
                               (assert (not (set-difference attribs
                                                            '("optional" "externsync"
                                                              "len" "noautovalidity")
                                                            :test 'string=)))
                            collect `(,desc
                                      ,@(when optional (list :optional optional))
                                      ,@(when len (list :len len))
                                      ,@(when noautovalidity (list :noautovalidity noautovalidity))
                                      ,@(when externsync (list :externsync externsync))))))
                (flet ((kw-list (x &key (translate #'make-keyword))
                         (mapcar translate
                                 (split-sequence:split-sequence #\, x :remove-empty-subseqs t))))
                  (setf (gethash name funcs)
                        (list (or (gethash type *vk-platform*) type)
                              params
                              :success (kw-list successcodes
                                                :translate 'make-const-keyword)
                              :errors (kw-list errorcodes
                                               :translate 'make-const-keyword)
                              :queues (kw-list queues)
                              :command-buffer-level (kw-list cmdbufferlevel)
                              :renderpass (kw-list renderpass))))))))

;;; TODO: feature
;;; extensions
      ;; mostly just expanding the enums, since the new struct/functions
      ;; definitions are included with core definitions earlier.
      ;; probably will eventually want to mark which names go with which
      ;; version/extension though.
      (xpath:do-node-set (node (xpath:evaluate "/registry/extensions/extension/require/enum" vk.xml))
        (let* ((ext (xps (xpath:evaluate "../../@name" node)))
               (ext-number (parse-integer
                            (xps (xpath:evaluate "../../@number" node))))
               (api (xps (xpath:evaluate "../../@supported" node)))
               (value (xps (xpath:evaluate "@value" node)))
               (.name (xps (xpath:evaluate "@name" node)))
               (name (make-const-keyword .name))
               (alias (xps (xpath:evaluate "@alias" node)))
               (extends (xps (xpath:evaluate "@extends" node)))
               (offset (xps (xpath:evaluate "@offset" node)))
               (bitpos (xps (xpath:evaluate "@bitpos" node)))
               (dir (xps (xpath:evaluate "@dir" node)))
               (attribs (attrib-names node)))
          (assert (not (set-difference attribs
                                       '("value" "name" "extends" "offset" "dir" "bitpos"
                                         ;; todo:
                                         "comment"
                                         ;; todo: only from v1.1.70
                                         "extnumber" "alias"
                                         )
                                       :test 'string=)))
          (if alias
              (progn
                (push .name alias-names)
                (warn "ALIAS NOT HANDLED YET: ~s is alias for ~s~%" .name alias))
              (progn
                (when (and (not extends)
                           (alexandria:ends-with-subseq "_EXTENSION_NAME" .name))
                  ;; todo: do something with the version/ext name enums
                  (setf (gethash ext extension-names)
                        (ppcre:regex-replace-all "&quot;" value "")))
                (when extends
                  (let ((extend (get-type extends)))
                    (assert (or (and offset (not value) (not bitpos))
                                ;; this was a special case for (string= .name "VK_SAMPLER_ADDRESS_MODE_MIRROR_CLAM_TO_EDGE") until version v1.1.70
                                (and (not offset) value (not bitpos))
                                (and (not offset) (not value) bitpos)))
                    (setf (getf extend :enum)
                          (append (getf extend :enum)
                                  (list (list .name (*
                                                     (if (equalp dir "-")
                                                         -1
                                                         1)
                                                     (or (and offset (+ *ext-base*
                                                                        (* *ext-block-size* (1- ext-number))
                                                                        (parse-integer offset)))
                                                         (and value (parse-integer value))
                                                         (and bitpos (ash 1 (parse-integer bitpos)))))
                                              :ext (format nil "~a" ext)))))))
                (format t "ext: ~s ~s ~s ~s ~s~%" value name extends (or offset value bitpos) dir)))))

      ;; and also mark which functions are from extensions
      (xpath:do-node-set (node (xpath:evaluate "/registry/extensions/extension/require/command" vk.xml))
        (let* ((ext (xps (xpath:evaluate "../../@name" node)))
               (name (xps (xpath:evaluate "@name" node)))
               (attribs (attrib-names node)))
          (if (find name alias-names :test #'string=)
              (warn "ALIAS NOT HANDLED YET: ~s is an alias~%" name) 
              (progn
                (assert (not (set-difference attribs
                                             '("name")
                                             :test 'string=)))
                (assert (gethash name funcs))
                (setf (getf (cddr (gethash name funcs)) :ext)
                      ext)
                (format t "extf: ~s ~s~%" name ext)))))

      (setf types (nreverse types))
 
      ;; WRITE PACKAGE 
      (write-types-file types-file copyright extension-names types bitfields structs vendor-ids)

      ;; write functions file
      (with-open-file (out funcs-file :direction :output :if-exists :supersede)
        (format out ";;; this file is automatically generated, do not edit~%")
        (format out "#||~%~a~%||#~%~%" copyright)
        (format out "(in-package #:cl-vulkan-bindings)~%~%")
        (loop for (name . attribs) in (sort (alexandria:hash-table-alist funcs)
                                            'string< :key 'car)
              for ret = (first attribs)
              for args = (second attribs)
              for success = (getf (cddr attribs) :success)
              for errors = (getf (cddr attribs) :errors)
              for queues = (getf (cddr attribs) :queues)
              for cbl = (getf (cddr attribs) :command-buffer-level)
              for ext = (getf (cddr attribs) :ext)
              do (format out "(~a (~s ~(~a) ~a~)"
                         (if ext *ext-definer* *core-definer*)
                         name
                         (fix-function-name name vendor-ids)
                         (cond
                           ((string-equal ret "VkResult")
                            "checked-result")
                           ((keywordp ret)
                            (format nil "~s" ret))
                           (t (fix-type-name ret vendor-ids))))
                 (loop with *print-right-margin* = 10000
                       for (arg . opts) in args
                       do (format out "~&  ~1{~((~a ~s)~)~}" arg)
                       when opts do (format out " ;; ~{~s~^ ~}~%" opts))
                 (format out ")~%~%")))

      ;; write package file
      (with-open-file (out binding-package-file
                           :direction :output :if-exists :supersede)
        (format out ";;; this file is automatically generated, do not edit~%")
        (format out "#||~%~a~%||#~%~%" copyright)
        (format out "(defpackage #:cl-vulkan-bindings~%  (:use #:cl #:cffi)~%")
        (format out "  (:nicknames #:%vk)~%")
        (format out "  (:export~%")
        (loop for (type . (typetype)) in (sort (copy-list types)
                                               'string< :key 'car)
              do (format out "~(    #:~a ;; ~s~)~%"
                         (fix-type-name type vendor-ids) typetype))
        (format out "~%")
        (loop for (func) in (sort (alexandria:hash-table-alist funcs)
                                  'string< :key 'car)
              do (format out "~(    #:~a~)~%" (fix-function-name func vendor-ids)))
        (format out "))~%"))

      ;; write struct translators
      ;; possibly should do this while dumping struct types?
      (with-open-file (out translators-file
                           :direction :output :if-exists :supersede)
        (format out ";;; this file is automatically generated, do not edit~%")
        (format out "#||~%~a~%||#~%~%" copyright)
        (format out "(in-package #:cl-vulkan-bindings)~%~%")
        (loop for (name . attribs) in (sort (remove-if-not
                                             (lambda (x)
                                               (and (consp (cdr x))
                                                    (member (second x)
                                                            '(:struct :union))))
                                             types)
                                            'string< :key 'car)
              for members = (getf (cddr attribs) :members)
              do (format out "~((def-translator ~a (deref-~a ~:[:fill fill-~a~;~])~)~%"
                         (fix-type-name name vendor-ids)
                         (fix-type-name name vendor-ids)
                         (getf (cddr attribs) :returned-only)
                         (fix-type-name name vendor-ids))
                 (loop for m in members
                       do (format out "~&  ~((:~{~s~^ ~})~)" m))
                 (format out ")~%~%")))

      ;; todo: print out changes
      (force-output)
      nil)))
