(uiop:define-package :vk-generator/versions
    (:use :cl)
  (:export :*versions*
           :get-xml-path))

(uiop:define-package :vk-generator/ensure-vk-xml
    (:use :cl
          :vk-generator/versions)
  (:export :make-vulkan-docs-name
           :make-vk-xml-name
           :make-zip-pathname
           :make-xml-pathname
           :download-vulkan-docs
           :extract-vk-xml
           :ensure-vk-xml))

;;; PARSER

(uiop:define-package :vk-generator/parser/constants
    (:use :cl)
  (:export :*special-words*
           :*fix-must-be*))

(uiop:define-package :vk-generator/parser/make-keyword
    (:use :cl)
  (:export :make-keyword
           :make-const-keyword))

(uiop:define-package :vk-generator/parser/xml-utils
    (:use :cl)
  (:export :xps
           :attrib-names))

(uiop:define-package :vk-generator/parser/numeric-value
    (:use :cl)
  (:export :numeric-value))

(uiop:define-package :vk-generator/parser/extract-vendor-ids
    (:use :cl
          :vk-generator/parser/xml-utils)
  (:export :extract-vendor-ids))

(uiop:define-package :vk-generator/parser/fix-name
    (:use :cl
     :vk-generator/parser/constants)
  (:export :fix-type-name
           :fix-function-name
           :fix-bit-name))

(uiop:define-package :vk-generator/generate
    (:use :cl
          :vk-generator/parser/constants
          :vk-generator/parser/make-keyword
          :vk-generator/parser/xml-utils
          :vk-generator/parser/numeric-value
          :vk-generator/parser/extract-vendor-ids
          :vk-generator/parser/fix-name)
  (:export :generate-vk-package))



(uiop:define-package :vk-generator/make-vk
    (:use :cl
          :vk-generator/versions
          :vk-generator/ensure-vk-xml
          :vk-generator/generate)
  (:export :make-vk))

;;; VK-GENERATOR

(uiop:define-package :vk-generator
    (:use :cl
          :vk-generator/versions
          :vk-generator/ensure-vk-xml
          :vk-generator/generate
          :vk-generator/make-vk)
  (:reexport :vk-generator/versions)
  (:reexport :vk-generator/ensure-vk-xml)  
  (:reexport :vk-generator/generate) 
  (:reexport :vk-generator/make-vk))
