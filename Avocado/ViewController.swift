
import UIKit
import CryptoSwift
import LocalAuthentication

class ViewController: UIViewController {
    
    private let appService = "AvocadoService"

    private enum DefaultKeys: String {
        case email
    }
    
    private enum TextFieldTag: Int {
        case email = 1001
        case password = 1002
    }
    
    private enum AuthState {
        case loggedIn, loggedOut
    }
    
    private var stackView: UIStackView!
    private var avocadoLabel: UILabel!
    
    private var isLoggedIn = false

    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupLayout()
        beginObserving()
        setInfoHeader(with: "Avocado", subtitle: "Login to view the avocado")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        attemptBiometrics()
    }
    
    // MARK: Notifications
    
    private func beginObserving() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didEnterBackground),
            name: .UIApplicationDidEnterBackground,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didBecomeActive),
            name: .UIApplicationDidBecomeActive,
            object: nil
        )
    }
    
    @objc private func didEnterBackground() {
        update(for: .loggedOut)
        print("background")
    }
    
    @objc private func didBecomeActive() {
        guard !isLoggedIn else {
            return
        }
        
        attemptBiometrics()
    }
    
    // MARK: Layout Helpers
    
    func setInfoHeader(with title: String, subtitle: String) {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textAlignment = .center
        
        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textAlignment = .center
        
        let titleStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        titleStack.spacing = 2
        titleStack.axis = .vertical
        titleStack.alignment = .center
        navigationItem.titleView = titleStack
    }
    
    private func setupLayout() {
        view.backgroundColor = .white
        let padding: CGFloat = 20
        
        let emailField = makeTextField(with: .email)
        let passwordField = makeTextField(with: .password)
        stackView = UIStackView(arrangedSubviews: [emailField, passwordField])
        
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.alignment = .fill
        stackView.spacing = padding
        stackView.axis = .vertical
        
        view.addSubview(stackView)
        
        let constraints: [NSLayoutConstraint] = [
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: padding),
            stackView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: padding),
            stackView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -padding)
        ]
        NSLayoutConstraint.activate(constraints)
    }
    
    private func makeTextField(with fieldTag: TextFieldTag) -> UITextField {
        let textField = UITextField()
        
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.enablesReturnKeyAutomatically = true
        textField.borderStyle = .roundedRect
        textField.tag = fieldTag.rawValue
        textField.delegate = self
        
        switch fieldTag {
        case .email:
            textField.placeholder = "Enter your email"
            textField.autocapitalizationType = .none
            textField.keyboardType = .emailAddress
            textField.returnKeyType = .next
            textField.text = savedEmail
        case .password:
            textField.placeholder = "Enter your password"
            textField.isSecureTextEntry = true
            textField.returnKeyType = .done
        }
        
        return textField
    }
    
    private func update(for authState: AuthState) {
        switch authState {
        case .loggedIn:
            isLoggedIn = true
            stackView?.isHidden = true
            
            avocadoLabel = UILabel()
            avocadoLabel.translatesAutoresizingMaskIntoConstraints = false
            avocadoLabel.font = UIFont.systemFont(ofSize: 50)
            avocadoLabel.text = "🥑"
            
            view.addSubview(avocadoLabel)
            let constraints: [NSLayoutConstraint] = [
                avocadoLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                avocadoLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ]
            NSLayoutConstraint.activate(constraints)

        case .loggedOut:
            isLoggedIn = false
            avocadoLabel?.isHidden = true
            stackView?.isHidden = false
            
            if let emailField = view.viewWithTag(TextFieldTag.email.rawValue) as? UITextField {
                emailField.text = savedEmail
            }
            if let passwordField = view.viewWithTag(TextFieldTag.password.rawValue) as? UITextField {
                passwordField.text = String()
            }
        }
    }
    
    // MARK: Login Helpers
    
    private var savedEmail: String? {
        return UserDefaults.standard.string(forKey: DefaultKeys.email.rawValue)
    }
    
    private func hasSavedCredentials() -> Bool {
        guard let email = savedEmail else {
            return false
        }
        
        do {
            let password = try KeychainPasswordItem(service: appService, account: email).readPassword()
            return !password.isEmpty
        }
        catch {
            return false
        }
    }
    
    private func input(for fieldTag: TextFieldTag) -> String? {
        guard let textField = view.viewWithTag(fieldTag.rawValue) as? UITextField else {
            return nil
        }
        
        return textField.text
    }
    
    private func attemptLogin() {
        guard let email = input(for: .email), let password = input(for: .password) else {
            return
        }
        
        loginUser(with: email, password: password)
        view.endEditing(true)
    }
    
    private func inputHash(from email: String, password: String) -> String {
        let count = 16
        var data = Data(count: count)
        _ = data.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, count, $0)
        }
        let salt = data.base64EncodedString()
        let components = [email, salt, password]
        return components.joined(separator: ".").sha256()
    }
    
    private func loginUser(with email: String, password: String) {
        let item = KeychainPasswordItem(service: appService, account: email)
        let hash = inputHash(from: email, password: password)
        
        do {
            try item.savePassword(hash)
            
            UserDefaults.standard.set(email, forKey: DefaultKeys.email.rawValue)
            UserDefaults.standard.synchronize()
            
            NotificationCenter.default.post(name: .loginStatusChanged, object: email)
            update(for: .loggedIn)
        }
        catch let e {
            print("Error saving to the keychain: \(e.localizedDescription).")
        }
    }
    
    private func attemptBiometrics() {
        guard hasSavedCredentials() else {
            return
        }
        
        checkBiometrics { success in
            guard success else {
                return
            }
            
            self.update(for: .loggedIn)
        }
    }
    
    private func checkBiometrics(completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        let reason = "App Authentication"
        let policy: LAPolicy = .deviceOwnerAuthenticationWithBiometrics
        
        if context.canEvaluatePolicy(policy, error: nil) {
            context.evaluatePolicy(policy, localizedReason: reason) { success, error in
                DispatchQueue.main.async {
                    completion(success)
                }
            }
        }
        else {
            completion(false)
        }
    }

}

// MARK: - UITextFieldDelegate

extension ViewController: UITextFieldDelegate {
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if let passwordField = view.viewWithTag(TextFieldTag.password.rawValue) as? UITextField, textField.tag == TextFieldTag.email.rawValue {
            if (passwordField.text?.count ?? 0) > 0 {
                attemptLogin()
            }
            else {
                passwordField.becomeFirstResponder()
            }
        }
        else {
            attemptLogin()
        }
        
        return true
    }
    
}

// MARK: - Notification.Name

extension Notification.Name {
    
    static let loginStatusChanged = Notification.Name(rawValue: "loginStatusChanged")
    
}
