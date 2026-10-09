defmodule Xamt.Storage.S3.Auth do
  @moduledoc false

  # Minimal AWS Signature Version 4 for path-style S3 (SeaweedFS).

  @service "s3"

  def sign(method, url, body, config, extra_headers \\ []) do
    uri = URI.parse(url)
    host = uri.authority || uri.host
    path = uri.path || "/"
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    amz_date = Calendar.strftime(now, "%Y%m%dT%H%M%SZ")
    date_stamp = Calendar.strftime(now, "%Y%m%d")
    payload_hash = sha256_hex(body || "")
    region = config.region

    base_headers = [
      {"host", host},
      {"x-amz-content-sha256", payload_hash},
      {"x-amz-date", amz_date}
    ]

    headers =
      (base_headers ++ normalize_headers(extra_headers))
      |> Enum.reject(fn {k, _} -> String.downcase(k) == "authorization" end)
      |> Enum.sort_by(fn {k, _} -> String.downcase(k) end)

    signed_headers =
      headers
      |> Enum.map(fn {k, _} -> String.downcase(k) end)
      |> Enum.join(";")

    canonical_headers =
      headers
      |> Enum.map(fn {k, v} -> "#{String.downcase(k)}:#{trim_all(v)}" end)
      |> Enum.join("\n")
      |> Kernel.<>("\n")

    canonical_request =
      [
        method_string(method),
        path,
        "",
        canonical_headers,
        signed_headers,
        payload_hash
      ]
      |> Enum.join("\n")

    credential_scope = "#{date_stamp}/#{region}/#{@service}/aws4_request"

    string_to_sign =
      [
        "AWS4-HMAC-SHA256",
        amz_date,
        credential_scope,
        sha256_hex(canonical_request)
      ]
      |> Enum.join("\n")

    signing_key =
      hmac_sha256("AWS4" <> config.secret_key, date_stamp)
      |> hmac_sha256(region)
      |> hmac_sha256(@service)
      |> hmac_sha256("aws4_request")

    signature = hmac_sha256_hex(signing_key, string_to_sign)

    authorization =
      "AWS4-HMAC-SHA256 Credential=#{config.access_key}/#{credential_scope}, " <>
        "SignedHeaders=#{signed_headers}, Signature=#{signature}"

    [{"authorization", authorization} | headers]
  end

  defp method_string(:get), do: "GET"
  defp method_string(:put), do: "PUT"
  defp method_string(:delete), do: "DELETE"
  defp method_string(:head), do: "HEAD"

  defp normalize_headers(headers) do
    Enum.map(headers, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), to_string(v)}
      {k, v} -> {to_string(k), to_string(v)}
    end)
  end

  defp trim_all(value) do
    value
    |> to_string()
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end

  defp sha256_hex(data) do
    :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
  end

  defp hmac_sha256(key, data) when is_binary(key) and is_binary(data) do
    :crypto.mac(:hmac, :sha256, key, data)
  end

  defp hmac_sha256_hex(key, data) do
    hmac_sha256(key, data) |> Base.encode16(case: :lower)
  end
end
