import Foundation

// =====================================================================
//  Strings.swift
//  Rdp Virtual Box App - macOS Native Client UI string tablosu.
//
//  PowerShell SetupUI.ps1 icindeki New-SetupUiStrings fonksiyonunun
//  Swift karsiligi. Turkce varsayilan, Ingilizce fallback. NSLocalizedString
//  kullanimina gecmek isterseniz Resources/*.lproj/Localizable.strings
//  altina tasinabilir; bu struct mevcut yapinin birebir karsiligidir.
// =====================================================================

public struct UiStrings {
    public let language: UILanguage

    public init(language: UILanguage) {
        self.language = language
    }

    public func tr(_ tr: String, _ en: String) -> String {
        language == .tr ? tr : en
    }

    // MARK: - Form & steps

    public var formTitle: String { tr("Rdp Virtual Box App - Kurulum", "Rdp Virtual Box App - Setup") }
    public var stepLabelFormat: String { tr("Adım {0}/4: {1}", "Step {0}/4: {1}") }
    public var step1Title: String { tr("Sunucu bilgileri", "Server information") }
    public var step2Title: String { tr("Sunucu tespit sonuçları", "Server probe results") }
    public var step3Title: String { tr("Uygulama ve erişim tipi", "Application and access type") }
    public var step4Title: String { tr("İnceleme ve kurulum", "Review and install") }

    public var serverIpLabel: String { tr("Sunucu IP:", "Server IP:") }
    public var portLabel: String { tr("Port:", "Port:") }
    public var usernameLabel: String { tr("Kullanıcı adı (domain\\user):", "Username (domain\\user):") }
    public var passwordLabel: String { tr("Parola:", "Password:") }
    public var probeButton: String { tr("Sunucuyu Tara", "Probe server") }
    public var backButton: String { tr("Geri", "Back") }
    public var nextButton: String { tr("İleri", "Next") }
    public var installButton: String { tr("Kurulumu Başlat", "Start install") }
    public var cancelButton: String { tr("İptal", "Cancel") }

    public var probeProgress: String { tr("Sunucu taranıyor, lütfen bekleyin...", "Probing server, please wait...") }
    public var componentHeader: String { tr("Bileşen", "Component") }
    public var statusHeader: String { tr("Durum", "Status") }
    public var valueHeader: String { tr("Değer", "Value") }
    public var recommendations: String { tr("Öneriler", "Recommendations") }

    public var chooseApps: String { tr("Kurulacak uygulamaları seçin (çoklu seçim):", "Select applications to install (multiple allowed):") }
    public var accessTypeLabel: String { tr("Erişim Tipi", "Access type") }
    public var credentialLabel: String { tr("Kimlik Bilgisi Yönetimi", "Credential handling") }
    public var customAppPath: String { tr("Özel uygulama yolu (opsiyonel):", "Custom application path (optional):") }
    public var summaryLabel: String { tr("Seçimlerinizi inceleyin:", "Review your selections:") }
    public var installingLabel: String { tr("Kurulum yapılıyor, lütfen bekleyin...", "Installing, please wait...") }
    public var confirmCancel: String { tr("Kurulumdan çıkmak istediğinize emin misiniz?", "Are you sure you want to exit the setup?") }
    public var confirmCancelCap: String { tr("Çıkışı Onayla", "Confirm exit") }

    public var errorTitle: String { tr("Hata", "Error") }
    public var warningTitle: String { tr("Uyarı", "Warning") }

    public var invalidIp: String { tr("Lütfen geçerli bir IPv4 veya hostname girin.", "Please enter a valid IPv4 or hostname.") }
    public var invalidPort: String { tr("Port 1 ile 65535 arasında olmalıdır.", "Port must be between 1 and 65535.") }
    public var invalidUser: String { tr("Kullanıcı adı DOMAIN\\kullanici veya kullanici@domain formatında olmalıdır.", "Username must be in DOMAIN\\user or user@domain format.") }
    public var missingPassword: String { tr("Parola boş olamaz.", "Password cannot be empty.") }
    public var probeFailed: String { tr("Sunucu taraması başarısız: {0}", "Server probe failed: {0}") }

    public var installDone: String { tr("Kurulum başarıyla tamamlandı.", "Setup completed successfully.") }

    public var statusOk: String { tr("TAMAM", "OK") }
    public var statusWarn: String { tr("UYARI", "WARNING") }
    public var statusError: String { tr("HATA", "ERROR") }

    public var embedWarning: String { tr(
        "Kimlik bilgisini RDP dosyasına gömmek güvenli değildir. Devam edilsin mi?",
        "Embedding credentials in RDP files is not secure. Continue?"
    ) }

    // MARK: - Localization helpers

    public func accessTypeName(_ type: AccessType) -> String {
        switch type {
        case .native: return tr("Native (.rdp dosyası) - ÖNERİLEN", "Native (.rdp file) - RECOMMENDED")
        case .web: return tr("Web (HTML5, tarayıcı)", "Web (HTML5, browser)")
        case .both: return tr("Her ikisi", "Both")
        }
    }

    public func credentialName(_ mode: CredentialMode) -> String {
        switch mode {
        case .ask: return tr("Her bağlantıda sor", "Ask on every connection")
        case .save: return tr("macOS Keychain'e kaydet", "Save to macOS Keychain")
        case .embed: return tr("RDP dosyasına göm (önerilmez)", "Embed in RDP file (not recommended)")
        }
    }

    public func languageName(_ lang: UILanguage) -> String {
        lang == .tr ? "Türkçe" : "English"
    }
}