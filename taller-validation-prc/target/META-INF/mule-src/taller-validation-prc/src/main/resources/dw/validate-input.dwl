%dw 2.0
output application/json
import * from dw::core::Numbers
var now = |2026-06-18| as Date // replace with now() when running live
// Helper: safe parse date in common formats, return null if fails
fun parseDate(d) =
  if (d == null) null
  else
    do {
      var attempts = [
        try (d as Date {format: "yyyy-MM-dd"}) catch null,
        try (d as Date {format: "dd/MM/yyyy"}) catch null,
        try (d as Date {format: "MM-dd-yyyy"}) catch null,
        try (d as Date) catch null
      ]
      ---
      attempts filter ($ != null) default []
    }[0] // first successful or null

// Compute age in years
fun ageFrom(d) =
  if (d == null) null
  else
    do {
      var years = now.year - d.year - ((now.month < d.month) or ((now.month == d.month) and (now.day < d.day)) ? 1 : 0)
      ---
      years
    }

var src = (payload) // payload will be the incoming JSON or XML parsed into DataWeave object

// Normalize helpers
fun trimLower(s) = if (s == null) null else (s as String) trim() toLower()
fun trimCap(s) = if (s == null) null else (s as String) trim()

// Extract flexible fields (supports multiple source shapes)
var customerId = src.customerId default src.id default src.externalId default src.customer?.id
var firstName = src.firstName default src.name?.first default src.name?.given
var lastName = src.lastName default src.name?.last default src.name?.family
var emailRaw = src.email default src.contact?.email
var dobRaw = src.dateOfBirth default src.dob default src.birthDate
var addressSrc = src.address default src.contact?.address default src.addresses?[0]

// Validation
var errors = []
---
(
  // Build validation array
  if (customerId == null) errors add "customerId or externalId is required" else null,
  if ((firstName default null) == null) errors add "firstName is required" else null,
  if ((lastName default null) == null) errors add "lastName is required" else null,
  if ((emailRaw default null) == null) errors add "email is required" else null
)
---
if (errors sizeOf > 0) {
  status: 400,
  error: "Validation failed",
  details: errors
}
else
  // Attempt to parse date
  var parsedDob = parseDate(dobRaw)
  var dobErrors = if (dobRaw != null and parsedDob == null) ["dateOfBirth could not be parsed"] else []
  ---
  if (dobErrors sizeOf > 0) {
    status: 400,
    error: "Validation failed",
    details: dobErrors
  }
  else
    // Success canonical object
    {
      status: 200,
      customer: {
        customerId: customerId as String,
        externalId: src.externalId default null,
        firstName: trimCap(firstName),
        lastName: trimCap(lastName),
        fullName: (trimCap(firstName) default "") ++ " " ++ (trimCap(lastName) default "") trim(),
        email: trimLower(emailRaw),
        dateOfBirth: parsedDob as Date {format: "yyyy-MM-dd"} default null,
        age: if (parsedDob == null) null else ageFrom(parsedDob),
        address: {
          street: (addressSrc?.line1 default addressSrc?.street default addressSrc?.streetLine default null) as String?,
          city: addressSrc?.city default null,
          state: addressSrc?.state default addressSrc?.region default null,
          postalCode: addressSrc?.postalCode default addressSrc?.zip default null,
          country: addressSrc?.country default "US"
        },
        sourceMeta: {
          sourceSystem: src.sourceSystem default null,
          receivedAt: |2026-06-18T00:00:00Z| as DateTime // placeholder; in Mule use now() formatted
        }
      }
    }