/// User model representing authenticated user data from the backend.
class User {
  const User({
    required this.id,
    required this.email,
    required this.companyId,
    required this.firstName,
    required this.lastName,
    this.middleName,
    required this.role,
    this.operatorNumber,
    this.defaultStorage,
    this.company,
  });

  final String id;
  final String email;
  final String companyId;
  final String firstName;
  final String lastName;
  final String? middleName;
  final String role;
  final String? operatorNumber;
  final String? defaultStorage;
  final Company? company;

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      companyId: json['companyId'] as String,
      firstName: json['firstName'] as String,
      lastName: json['lastName'] as String,
      middleName: json['middleName'] as String?,
      role: json['role'] as String,
      operatorNumber: json['operatorNumber'] as String?,
      defaultStorage: json['defaultStorage'] as String?,
      company: json['company'] != null
          ? Company.fromJson(json['company'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'companyId': companyId,
      'firstName': firstName,
      'lastName': lastName,
      if (middleName != null) 'middleName': middleName,
      'role': role,
      if (operatorNumber != null) 'operatorNumber': operatorNumber,
      if (defaultStorage != null) 'defaultStorage': defaultStorage,
      if (company != null) 'company': company!.toJson(),
    };
  }
}

/// Company model representing company data.
class Company {
  const Company({
    required this.id,
    required this.name,
    required this.type,
    required this.usesSupto,
    required this.vat,
    this.currencyDefault,
    this.country,
  });

  final String id;
  final String name;
  final String type;
  final bool usesSupto;
  final String vat;
  final CurrencyDefault? currencyDefault;
  final Country? country;

  factory Company.fromJson(Map<String, dynamic> json) {
    return Company(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      usesSupto: json['usesSupto'] as bool,
      vat: json['vat'] as String,
      currencyDefault: json['currency_default'] != null
          ? CurrencyDefault.fromJson(
              json['currency_default'] as Map<String, dynamic>,
            )
          : null,
      country: json['country'] != null
          ? Country.fromJson(json['country'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'usesSupto': usesSupto,
      'vat': vat,
      if (currencyDefault != null)
        'currency_default': currencyDefault!.toJson(),
      if (country != null) 'country': country!.toJson(),
    };
  }
}

/// Currency default model.
class CurrencyDefault {
  const CurrencyDefault({
    required this.id,
    required this.title,
    required this.code,
    required this.symbol,
    required this.symbolPosition,
    required this.exchangeRate,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String code;
  final String symbol;
  final String symbolPosition;
  final double exchangeRate;
  final bool isActive;
  final String createdAt;
  final String updatedAt;

  factory CurrencyDefault.fromJson(Map<String, dynamic> json) {
    return CurrencyDefault(
      id: json['id'] as String,
      title: json['title'] as String,
      code: json['code'] as String,
      symbol: json['symbol'] as String,
      symbolPosition: json['symbol_position'] as String,
      exchangeRate: (json['exchange_rate'] as num).toDouble(),
      isActive: json['is_active'] as bool,
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'code': code,
      'symbol': symbol,
      'symbol_position': symbolPosition,
      'exchange_rate': exchangeRate,
      'is_active': isActive,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
}

/// Country model.
class Country {
  const Country({required this.id, required this.code});

  final String id;
  final String code;

  factory Country.fromJson(Map<String, dynamic> json) {
    return Country(id: json['id'] as String, code: json['code'] as String);
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'code': code};
  }
}

/// Authenticated user response model.
class AuthenticatedUserResponse {
  const AuthenticatedUserResponse({
    required this.user,
    this.settings,
    this.config,
    this.hmac,
  });

  final User user;
  final List<Map<String, dynamic>>? settings;
  final Map<String, dynamic>? config;
  final String? hmac;

  factory AuthenticatedUserResponse.fromJson(Map<String, dynamic> json) {
    return AuthenticatedUserResponse(
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      settings: json['settings'] != null
          ? (json['settings'] as List)
                .map((e) => e as Map<String, dynamic>)
                .toList()
          : null,
      config: json['config'] as Map<String, dynamic>?,
      hmac: json['hmac'] as String?,
    );
  }
}
