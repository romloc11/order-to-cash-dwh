{% docs aging_bucket %}
Lateness category of an invoice, based on `days_late`:

| Value | Meaning |
|---|---|
| `cleared` | The invoice has already been paid or settled |
| `not_due` | Open and not yet past its due date |
| `1-15` | Open, 1 to 15 days past due |
| `16-30` | Open, 16 to 30 days past due |
| `31-60` | Open, 31 to 60 days past due |
| `60+` | Open, more than 60 days past due |
{% enddocs %}
