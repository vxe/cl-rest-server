(in-package :rest-server.auth)

(defparameter *resource-server-id* "a7c87ae0-dabe-4b8a-8a45-ee9708696794")
(defparameter *resource-server-secret* "443c188d-60ce-40e2-b268-69c0c78ad055")
(defparameter *oauth2-server-url* "http://localhost:8080")

(defclass oauth2-authorization ()
  ((scopes :initarg :scopes
           :initform nil
           :documentation "Auth scopes")))

(defmethod scopes ((authorization oauth2-authorization))
  (mapcar (lambda (symbol-or-string)
            (if (stringp symbol-or-string)
                symbol-or-string
                (string-downcase (symbol-name symbol-or-string))))
          (slot-value authorization 'scopes)))

(defmethod authorize ((authorization oauth2-authorization) resource-operation)
  (flet ((auth-failed (message)
           (log5:log-for (rs::rest-server) "OAuth2 authorization failed: ~A" message)
           (return-from authorize (auth-fail message)))
         (auth-succeeded (authorized-token)
           (log5:log-for (rs::rest-server) "OAuth2 authorization: ~A" authorized-token)
           (return-from authorize
             (auth-success authorized-token))))
    (let* ((access-token (hunchentoot:header-in* "Authorization")))
      ;; if there's no access token, error
      (if (not access-token)
          (progn
            (log5:log-for (rs::rest-server) "Access token not provided")
            (auth-not-present "Provide the token"))
          ;; else, verify the access token
          (let* ((token-type-and-value (split-sequence:split-sequence #\space  access-token))
                 (token-type (first token-type-and-value))
                 (token-string (second token-type-and-value)))
            ;; Check it is a Bearer token
            (if (not (equalp token-type "Bearer"))
                (auth-failed "Not a Bearer token")
                (multiple-value-bind (result status)
                    (verify-access-token token-string)
                  ;; if not valid, error
                  (if (not (equalp status 200))
                      (auth-failed "Invalid token")
                      ;; else, check that the scopes are ok
                      (let ((token-scopes (getf result :scopes)))
                        (if (not (every (lambda (scope)
                                          (member scope token-scopes :test #'equalp))
                                        (scopes authorization)))
                            (auth-failed "Scope not sufficient")
                            ;; else, success
                            (auth-succeeded result)))))))))))

(defun verify-access-token (access-token)

  "GET https://<domain-name-authorization-server>/v1/tokeninfo?access_token=<access_token>
Authorization: Basic <Base64 encoded key:secret >
Accept: application/json"

                                        ;(break "verify access token: ~A" access-token)
  (let ((uri (puri:merge-uris (format nil "/v1/tokeninfo?access_token=~A" access-token) *oauth2-server-url*))
        (authorization (base64:string-to-base64-string
                        (format nil "~A:~A"
                                *resource-server-id*
                                *resource-server-secret*))))
      (multiple-value-bind (result status)
          (drakma:http-request
           uri
           :method :get
           :accept "application/json"
           :additional-headers `(("Authorization" . ,(format nil "Basic ~A" authorization)))
           :parameters nil)
        (values (alexandria:alist-plist
                   (with-lisp-json
                     (json:decode-json-from-string result)))
                status))))

(defun exchange-authorization-code (code redirect-uri client-id client-secret &optional (grant-type "authorization_code"))
  (with-lisp-json
    (let ((uri (puri:merge-uris "/oauth2/token" *oauth2-server-url*))
          (content (json:encode-json-plist-to-string (list :code code
                                                           :grant-type grant-type
                                                           :redirect-uri redirect-uri)))
          (authorization
           (cl-base64:string-to-base64-string
            (format nil "~A:~A" client-id client-secret))))
      (multiple-value-bind (result status)
          (drakma:http-request
           (puri:render-uri uri nil)
           :method :post
           :accept "application/json"
           :additional-headers `(("Authorization" . ,(format nil "Basic ~A" authorization)))

           :parameters `(("code" . ,code)
                         ("grant_type" . ,grant-type)
                         ("redirect_uri" . ,redirect-uri)))
        (values (alexandria:alist-plist
                 (json:decode-json-from-string result))
                status)))))
