class ApiError(Exception):
    status_code = 500
    message = "Internal server error."
    code = None

    def __init__(self, message=None, status_code=None, code=None):
        super().__init__(message or self.message)
        self.message = message or self.message
        self.status_code = status_code or self.status_code
        self.code = code if code is not None else self.code

    def to_dict(self):
        payload = {"error": self.message}
        if self.code:
            payload["code"] = self.code
        return payload


class ValidationError(ApiError):
    status_code = 400


class ForbiddenError(ApiError):
    status_code = 403


class NotFoundError(ApiError):
    status_code = 404


class ConflictError(ApiError):
    status_code = 409


class DatabaseOperationError(ApiError):
    status_code = 500
    message = "Database error."

    def __init__(self, operation, original):
        super().__init__(self.message, self.status_code)
        self.operation = operation
        self.original = original

    def to_dict(self):
        payload = super().to_dict()
        payload["source"] = self.operation
        return payload
