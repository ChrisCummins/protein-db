(ns pip-db.views.login
  (:use [pip-db.views.layout :only (page)]
        [hiccup.form :only (form-to label)]))

(defn login []
  (page {:title "Sign in"
         :header [:style
"body {
  background: #eee;
  padding: 40px auto;
}"]
         :body [:form.form-signin {:method "post" :action "/login"}
                [:h2.form-signin-heading "Login"]
                [:input.form-control {:name "user" :type "text"
                                      :autocomplete "off"
                                      :placeholder "Email address"}]
                [:input.form-control {:name "pass" :type "password"
                                      :placeholder "Password"}]
                [:label.checkbox [:input {:type "checkbox"
                                          :value "remember-me"}
                                  "Remember me"]]

                [:div {:style "display: table; width: 100%;"}
                 [:div {:style (str "display: table-cell; "
                                    "width: 50%; padding-right: 8px;")}
                  [:button.btn.btn-lg.btn-block.btn-primary
                   {:name "action" :value "register"}
                   "Register"]]
                 [:div {:style (str "display: table-cell; "
                                    "width: 50%; padding-left: 8px;")}
                  [:button.btn.btn-lg.btn-block.btn-success
                   {:name "action" :type "submit" :value "login"}
                   "Sign in"]]]]
         :hide-footer true}))
