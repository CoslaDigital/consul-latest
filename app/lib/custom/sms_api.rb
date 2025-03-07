load Rails.root.join("app", "lib", "sms_api.rb")
require "notifications/client"
require "open-uri"

class SmsApi
  attr_accessor :client

  def initialize
 #   @client = Savon.client(wsdl: url)
   @client = Notifications::Client.new(Tenant.current_secrets.sms_api_key)
  end

#  def url
#    return "" unless end_point_available?
#
#    URI.parse(Tenant.current_secrets.sms_end_point).to_s
#  end

#  def authorization
#    Base64.encode64("#{Tenant.current_secrets.sms_username}:#{Tenant.current_secrets.sms_password}")
#  end

  def sms_deliver(phone, code)
  #  return stubbed_response unless end_point_available?
    puts "Starting sms_deliver method"
    puts "phone number #{phone}"
    puts "code: #{code}"
    smsresponse = client.send_sms(
      phone_number: phone,
      template_id: "3e91c951-f3b5-4a35-a432-411f7f6c24ff",
      personalisation: message(phone,code)
      )
    log_sms_response(smsresponse)
    sms_success?(smsresponse)
  end

  def message(phone, code)
    {name: "Dummy User",
     token: code,
     link: "https://dev.communitychoices.scot"
    }
  end
   
#  def request(phone, code)
#    { autorizacion: authorization,
#      destinatarios: { destinatario: phone },
#      texto_mensaje: "Clave para verificarte: #{code}. Gobierno Abierto",
#      solicita_notificacion: "All" }
#  end
  
  def sms_success?(response)
    response.id.present? && response.reference.present?
  end

  def log_sms_response(response)
    puts "Notification ID: #{response.id}"
    puts "Reference: #{response.reference}"
    puts "Message Body: #{response.content[:body]}"
    puts "From Number: #{response.content[:from_number]}"
    puts "Template ID: #{response.template[:id]}"
    puts "Template Version: #{response.template[:version]}"
    puts "Template URI: #{response.template[:uri]}"
    puts "Notification URL: #{response.uri}"
  end
  
#  def success?(response)
#    response.body[:respuesta_sms][:respuesta_servicio_externo][:texto_respuesta] == "Success"
#  end

  def end_point_available?
    Rails.env.staging? || Rails.env.preproduction? || Rails.env.production?
  end

  def stubbed_response
    {
      respuesta_sms: {
        identificador_mensaje: "1234567",
        fecha_respuesta: "Thu, 20 Aug 2015 16:28:05 +0200",
        respuesta_pasarela: {
          codigo_pasarela: "0000",
          descripcion_pasarela: "Operación ejecutada correctamente."
        },
        respuesta_servicio_externo: {
          codigo_respuesta: "1000",
          texto_respuesta: "Success"
        }
      }
    }
  end
end
