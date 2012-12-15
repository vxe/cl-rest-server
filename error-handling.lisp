(in-package :rest-server)

;; Error handling configuration

(defvar *catch-conditions-p* t)
(defvar *development-mode* :production "Api development mode. One of :development, :testing, :production. Influences how errors are handled from the api")

;; Conditions

(define-condition http-error (simple-error)
  ((status-code :initarg :status-code
                :initform (error "Provide the status code")
                :accessor status-code))
  (:report (lambda (c s)
             (format s "HTTP error ~A" (status-code c)))))

(defun http-error (status-code)
  (error 'http-error :status-code status-code))

(define-condition http-not-found-error (http-error)
  ()
  (:default-initargs
   :status-code 404))

(define-condition http-internal-server-error (http-error)
  ()
  (:default-initargs
   :status-code 500))

(define-condition http-authorization-required-error (http-error)
  ()
  (:default-initargs
   :status-code 401))

(define-condition http-forbidden-error (http-error)
  ()
  (:default-initargs
   :status-code 403))

(defparameter *http-status-codes-conditions*
  '((404 . http-not-found-error)
    (401 . http-authorization-required-error)
    (403 . http-forbidden-error)
    (500 . http-internal-server-error)))

(defvar *conditions-mapping* nil "Assoc list mapping application conditions to HTTP conditions. (.i.e. permission-denied-error to http-forbidden-error)")

(defgeneric decode-response (response content-type)
  (:method (response content-type)
    (error "Not implemented")))

(defmethod decode-response (response (content-type (eql :json)))
  (json:decode-json-from-string
          (sb-ext:octets-to-string
           response
           :external-format :utf8)))

(defun handle-response (response status-code content-type)
  (cond
    ((and (>= status-code 200)
          (< status-code 400))
     (decode-response response content-type))
    ((assoc status-code *http-status-codes-conditions*)
     (error (cdr (assoc status-code *http-status-codes-conditions*))))
    (t (http-error status-code))))

(defmacro with-condition-handling (&body body)
  `(%with-condition-handling (lambda () (progn ,@body))))

(define-condition harmless-condition ()
  ()
  (:documentation "Inherit your condition from this if you dont want your condition to be catched by the error handler. (.i.e validation-errors to be serialized to the server, always)"))

(defun %with-condition-handling (function)
  (labels ((http-return-code (condition)
             (cond
	       ((typep condition 'http-error) (status-code condition))
               ((typep condition 'error) hunchentoot:+http-internal-server-error+)
               (t hunchentoot:+http-ok+)))
           (handle-condition (condition)
             (if (typep condition 'harmless-condition)
                 (serialize condition)
		 (progn
                   (setf (hunchentoot:return-code*) (http-return-code condition))
                   (when (not (equalp *development-mode* :production))
                     (serialize condition))))))
    (if *catch-conditions-p* 
        (handler-case (funcall function)
          (condition (c)
            (handle-condition c)))
	(handler-case (funcall function)
	  (harmless-condition (c)
	    (serialize c))))))

(defmethod serialize-value ((serializer (eql :json)) (error simple-error) stream) 
  "Serialize error condition"
  (json:encode-json-alist 
   (list (cons :condition (type-of error))
	 (cons :message (simple-condition-format-control error)))
   stream))

(defmethod serialize-value ((serializer (eql :json))
			    (error simple-error) 
			    stream)
  "Serialize simple error condition"
  (json:with-object (stream)
    (json:as-object-member (:condition stream)
      (json:encode-json (type-of error) stream))
    (json:as-object-member (:message stream)
      (json:encode-json (simple-condition-format-control error) stream))))