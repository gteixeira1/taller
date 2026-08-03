%dw 2.0
output application/json
import * from dw::core::Numbers
import * from dw::Runtime

// Helper: safe parse date in common formats, return null if fails
fun parseDate(d) =
  if (d == null) null
  else
    do {
      var attempts = [
          //try(() -> user.name!) orElse "No User Name",
        (try (() -> (d as Date {format: "yyyy-MM-dd"})) orElse null),
        (try (() -> (d as Date {format: "dd/MM/yyyy"})) orElse null),
        (try (() -> (d as Date {format: "MM-dd-yyyy"})) orElse null),
        (try (() -> (d as Date)) orElse null)
      ]
      ---
      (attempts filter ($ != null))[0] default null
    } // first successful or null

// Compute age in years
fun ageFrom(d) =
  if (d == null) null
  else
    do {
      var years = now.year - d.year - (
      	if((now.month < d.month) or ((now.month == d.month) and (now.day < d.day))) 1
		else 0
      )
      ---
      years
    }

// Normalize helpers
fun trimLower(s) = if (s == null) null else lower(trim((s as String)))
fun trimCap(s) = if (s == null) null else trim(s as String)

var now = |2026-06-18| as Date // replace with now() when running live

var src = (payload) // payload will be the incoming JSON or XML parsed into DataWeave object

// Extract flexible fields (supports multiple source shapes)
var customerId = src.customerId default src.id default src.externalId default src.customer.id default null
var firstName = src.firstName default src.name.first default src.name.given default null
var lastName = src.lastName default src.name.last default src.name.family default null
var emailRaw = src.email default src.contact.email default null
var dobRaw = src.dateOfBirth default src.dob default src.birthDate default null
var addressSrc = src.address default src.contact.address default src.addresses[0] default null

// Validation
var errors = [
  // Build validation array
  (
      if (customerId == null) 
        "customerId or externalId is required" 
      else null
  ),
  (
      if ((firstName default null) == null)
        "firstName is required"
     else null
  ),
  (
      if ((lastName default null) == null)
        "lastName is required"
      else null
  ),
  (
      if ((emailRaw default null) == null)
        "email is required"
      else null
  )
]

---
if (sizeOf(errors) > 0) {
  status: 400,
  error: "Validation failed",
  details: errors
}
else do {
  // Attempt to parse date
  var parsedDob = parseDate(dobRaw)
  var dobErrors = if (dobRaw != null and parsedDob == null) ["dateOfBirth could not be parsed"] else []
  ---
  if (sizeOf(dobErrors)  > 0) {
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
        fullName: trim((trimCap(firstName) default "") ++ " " ++ (trimCap(lastName) default "")),
        email: trimLower(emailRaw),
        dateOfBirth: parsedDob as Date {format: "yyyy-MM-dd"} default null,
        age: if (parsedDob == null) null else ageFrom(parsedDob),
        address: {
          street: (addressSrc.line1 default addressSrc.street default addressSrc.streetLine default null) as String,
          city: addressSrc.city default null,
          state: addressSrc.state default addressSrc.region default null,
          postalCode: addressSrc.postalCode default addressSrc.zip default null,
          country: addressSrc.country default "US"
        },
        sourceMeta: {
          sourceSystem: src.sourceSystem default null,
          receivedAt: |2026-06-18T00:00:00Z| as DateTime // placeholder; in Mule use now() formatted
        }
      }
    }
}
